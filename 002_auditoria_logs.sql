-- =============================================================
-- VOTO SEGURO 2026 — Auditoría y Logs
-- Estrategia: log SMART — solo mutaciones, no SELECTs
-- Costo: $0 (rows en Supabase Free Tier — 500MB incluidos)
-- =============================================================

-- =============================================================
-- 1. TABLA AUDIT_LOG
-- =============================================================
-- Escritura únicamente — NUNCA hacer UPDATE ni DELETE aquí.
-- Actúa como append-only ledger de cambios.
CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGSERIAL PRIMARY KEY,
    tabla           VARCHAR(100) NOT NULL,
    operacion       VARCHAR(10)  NOT NULL,   -- INSERT | UPDATE | DELETE
    id_registro     TEXT,                    -- PK del registro afectado (como texto)
    datos_antes     JSONB,                   -- NULL en INSERT
    datos_despues   JSONB,                   -- NULL en DELETE
    usuario_db      TEXT DEFAULT current_user,
    app_fuente      VARCHAR(50),             -- 'etl-jne' | 'api' | 'web' | 'manual'
    ip_origen       INET,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices mínimos — solo los necesarios para investigar incidentes
CREATE INDEX IF NOT EXISTS idx_audit_tabla_op
    ON audit_log(tabla, operacion);
CREATE INDEX IF NOT EXISTS idx_audit_created
    ON audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_id_registro
    ON audit_log(id_registro);

-- RLS: solo service_role puede leer audit_log (no el frontend anónimo)
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_log_service_only ON audit_log
    FOR ALL USING (auth.role() = 'service_role');

COMMENT ON TABLE audit_log IS
    'Append-only. Registra INSERT/UPDATE/DELETE en tablas críticas. '
    'Purgar entradas > 90 días tipo INSERT del ETL vía cron.';


-- =============================================================
-- 2. FUNCIÓN TRIGGER GENÉRICA
-- =============================================================
-- Optimización de costos:
-- - En UPDATE: solo loguea si cambió algo distinto a updated_at
-- - app.fuente: variable de sesión que el ETL/API debe setear con
--   SET LOCAL app.fuente = 'etl-jne';
CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER   -- corre con permisos del dueño, no del caller
SET search_path = public
AS $$
DECLARE
    v_id TEXT;
BEGIN
    -- Obtener PK como texto (soporta cualquier tabla con id_hoja_vida o id)
    IF TG_OP = 'DELETE' THEN
        v_id := COALESCE(
            OLD.id_hoja_vida::TEXT,
            OLD.id::TEXT
        );
    ELSE
        v_id := COALESCE(
            NEW.id_hoja_vida::TEXT,
            NEW.id::TEXT
        );
    END IF;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log(tabla, operacion, id_registro, datos_despues, app_fuente)
        VALUES (
            TG_TABLE_NAME,
            'INSERT',
            v_id,
            to_jsonb(NEW),
            current_setting('app.fuente', true)  -- true = no error si no está seteado
        );

    ELSIF TG_OP = 'UPDATE' THEN
        -- Evitar ruido: solo loguear si cambió algo más que updated_at
        IF (to_jsonb(NEW) - 'updated_at') <> (to_jsonb(OLD) - 'updated_at') THEN
            INSERT INTO audit_log(tabla, operacion, id_registro, datos_antes, datos_despues, app_fuente)
            VALUES (
                TG_TABLE_NAME,
                'UPDATE',
                v_id,
                to_jsonb(OLD),
                to_jsonb(NEW),
                current_setting('app.fuente', true)
            );
        END IF;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log(tabla, operacion, id_registro, datos_antes, app_fuente)
        VALUES (
            TG_TABLE_NAME,
            'DELETE',
            v_id,
            to_jsonb(OLD),
            current_setting('app.fuente', true)
        );
    END IF;

    RETURN NEW;
END;
$$;


-- =============================================================
-- 3. APLICAR TRIGGERS A TABLAS CRÍTICAS
-- =============================================================
-- Solo auditamos tablas que realmente importan.
-- Las tablas de detalle (educacion, experiencia, etc.) se auditan
-- a través del JSON en hojas_vida — no necesitan trigger individual.

-- candidatos: tabla más crítica (datos de candidatos)
DROP TRIGGER IF EXISTS trg_audit_candidatos ON candidatos;
CREATE TRIGGER trg_audit_candidatos
    AFTER INSERT OR UPDATE OR DELETE ON candidatos
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- hojas_vida: el JSON raw completo
DROP TRIGGER IF EXISTS trg_audit_hojas_vida ON hojas_vida;
CREATE TRIGGER trg_audit_hojas_vida
    AFTER INSERT OR UPDATE OR DELETE ON hojas_vida
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- organizaciones_politicas: raramente cambia, pero crítico si alguien borra un partido
DROP TRIGGER IF EXISTS trg_audit_org_pol ON organizaciones_politicas;
CREATE TRIGGER trg_audit_org_pol
    AFTER INSERT OR UPDATE OR DELETE ON organizaciones_politicas
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();


-- =============================================================
-- 4. FUNCIÓN AUTO-UPDATE updated_at
-- =============================================================
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Aplicar a tablas con updated_at
DROP TRIGGER IF EXISTS trg_updated_at_candidatos ON candidatos;
CREATE TRIGGER trg_updated_at_candidatos
    BEFORE UPDATE ON candidatos
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_updated_at_hojas_vida ON hojas_vida;
CREATE TRIGGER trg_updated_at_hojas_vida
    BEFORE UPDATE ON hojas_vida
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_updated_at_org_pol ON organizaciones_politicas;
CREATE TRIGGER trg_updated_at_org_pol
    BEFORE UPDATE ON organizaciones_politicas
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- =============================================================
-- 5. PURGA AUTOMÁTICA DE LOGS ANTIGUOS (cron via pg_cron)
-- =============================================================
-- Ejecutar mensualmente. Mantener:
--   - TODOS los UPDATE y DELETE (son sospechosos, conservar 1 año)
--   - Solo últimos 90 días de INSERT del ETL normal
-- OJO: pg_cron está disponible en Supabase. Habilitar en:
--      Dashboard > Database > Extensions > pg_cron

-- Descomentar cuando confirmes que pg_cron está habilitado:
/*
SELECT cron.schedule(
    'purgar-audit-log-etl',
    '0 3 1 * *',   -- 3am el día 1 de cada mes
    $$
        DELETE FROM audit_log
        WHERE created_at < NOW() - INTERVAL '90 days'
          AND operacion = 'INSERT'
          AND app_fuente = 'etl-jne';
    $$
);
*/

-- Versión manual (correr cuando sea necesario):
-- DELETE FROM audit_log
-- WHERE created_at < NOW() - INTERVAL '90 days'
--   AND operacion = 'INSERT'
--   AND app_fuente = 'etl-jne';

