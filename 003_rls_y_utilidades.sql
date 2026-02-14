-- =============================================================
-- VOTO SEGURO 2026 — RLS + Políticas de acceso + Utilidades
-- Principio: mínimo privilegio por rol
-- Roles Supabase: anon | authenticated | service_role
-- =============================================================

-- =============================================================
-- 1. ROW LEVEL SECURITY — tablas de candidatos (lectura pública)
-- =============================================================
-- Los datos de candidatos son PÚBLICOS (fuente: JNE).
-- El frontend anónimo puede leer, NUNCA escribir.

ALTER TABLE organizaciones_politicas    ENABLE ROW LEVEL SECURITY;
ALTER TABLE procesos_electorales        ENABLE ROW LEVEL SECURITY;
ALTER TABLE candidatos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hojas_vida                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE declaracion_ingresos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE educacion                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE experiencia_laboral         ENABLE ROW LEVEL SECURITY;
ALTER TABLE trayectoria                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE sentencias                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE bienes_inmuebles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE bienes_muebles              ENABLE ROW LEVEL SECURITY;

-- Lectura pública (anon + authenticated) para todas las tablas de candidatos
CREATE POLICY "lectura_publica" ON organizaciones_politicas
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON procesos_electorales
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON candidatos
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON hojas_vida
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON declaracion_ingresos
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON educacion
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON experiencia_laboral
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON trayectoria
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON sentencias
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON bienes_inmuebles
    FOR SELECT USING (true);
CREATE POLICY "lectura_publica" ON bienes_muebles
    FOR SELECT USING (true);

-- Escritura SOLO para service_role (el ETL corre con service_role)
-- anon y authenticated NO pueden INSERT/UPDATE/DELETE
-- (el default de RLS sin política de escritura = denegado)


-- =============================================================
-- 2. VISTA: candidatos_resumen
-- =============================================================
-- Vista liviana para el simulador y listas del frontend.
-- Evita que el cliente haga SELECT * (trae solo lo necesario).
-- No incluye domicilio_direccion ni datos sensibles.
CREATE OR REPLACE VIEW candidatos_resumen AS
SELECT
    c.id_hoja_vida,
    c.id_proceso_electoral,
    c.id_organizacion_politica,
    c.organizacion_politica_nombre,
    c.nombres,
    c.apellido_paterno,
    c.apellido_materno,
    -- Nombre completo calculado
    TRIM(c.apellido_paterno || ' ' || c.apellido_materno
         || ', ' || c.nombres)                      AS nombre_completo,
    c.sexo,
    c.cargo,
    c.numero_candidato,
    c.ubigeo_postula,
    c.departamento_postula,
    c.provincia_postula,
    c.distrito_postula,
    c.estado,
    -- URL de foto (construida desde el GUID)
    CASE
        WHEN c.tx_guid_foto IS NOT NULL
        THEN 'https://declara.jne.gob.pe/ASSETS/FOTOCANDIDATO/'
             || c.tx_nombre_archivo
        ELSE NULL
    END                                             AS url_foto,
    c.fecha_termino_registro
FROM candidatos c
WHERE c.estado = 'INSCRITO';   -- solo candidatos vigentes

COMMENT ON VIEW candidatos_resumen IS
    'Vista liviana para el frontend. Solo campos públicos, sin domicilio.';


-- =============================================================
-- 3. VISTA: candidatos_con_sentencias
-- =============================================================
-- Para el módulo de transparencia: candidatos CON sentencias.
CREATE OR REPLACE VIEW candidatos_con_sentencias AS
SELECT
    c.id_hoja_vida,
    c.nombre_completo,
    c.organizacion_politica_nombre,
    c.cargo,
    c.departamento_postula,
    s.tipo,
    s.detalle
FROM candidatos_resumen c
JOIN sentencias s ON s.id_hoja_vida = c.id_hoja_vida
WHERE s.tiene_sentencia = TRUE;


-- =============================================================
-- 4. FUNCIÓN: stats_por_cargo()
-- =============================================================
-- Retorna conteo de candidatos por cargo y organización.
-- Usada por el dashboard. Sin parámetros = baja complejidad.
CREATE OR REPLACE FUNCTION stats_por_cargo(p_proceso INTEGER DEFAULT 124)
RETURNS TABLE (
    cargo                   TEXT,
    id_organizacion         INTEGER,
    organizacion_nombre     TEXT,
    total_candidatos        BIGINT,
    total_mujeres           BIGINT,
    total_hombres           BIGINT
)
LANGUAGE sql
STABLE        -- no modifica datos, permite cache por Supabase
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        c.cargo,
        c.id_organizacion_politica,
        c.organizacion_politica_nombre,
        COUNT(*)                                    AS total_candidatos,
        COUNT(*) FILTER (WHERE c.sexo = '2')        AS total_mujeres,
        COUNT(*) FILTER (WHERE c.sexo = '1')        AS total_hombres
    FROM candidatos c
    WHERE c.id_proceso_electoral = p_proceso
      AND c.estado = 'INSCRITO'
    GROUP BY c.cargo, c.id_organizacion_politica, c.organizacion_politica_nombre
    ORDER BY c.cargo, total_candidatos DESC;
$$;


-- =============================================================
-- 5. FUNCIÓN: buscar_candidato(texto)
-- =============================================================
-- Búsqueda full-text por nombre usando trigram (pg_trgm).
-- Retorna máximo 20 resultados para no sobrecargar.
CREATE OR REPLACE FUNCTION buscar_candidato(
    p_texto     TEXT,
    p_proceso   INTEGER DEFAULT 124,
    p_limite    INTEGER DEFAULT 20
)
RETURNS TABLE (
    id_hoja_vida            INTEGER,
    nombre_completo         TEXT,
    cargo                   TEXT,
    organizacion_nombre     TEXT,
    departamento_postula    VARCHAR,
    url_foto                TEXT,
    similitud               REAL
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        c.id_hoja_vida,
        TRIM(c.apellido_paterno || ' ' || c.apellido_materno || ', ' || c.nombres),
        c.cargo,
        c.organizacion_politica_nombre,
        c.departamento_postula,
        CASE WHEN c.tx_guid_foto IS NOT NULL
             THEN 'https://declara.jne.gob.pe/ASSETS/FOTOCANDIDATO/' || c.tx_nombre_archivo
             ELSE NULL END,
        similarity(
            c.nombres || ' ' || c.apellido_paterno || ' ' || c.apellido_materno,
            p_texto
        ) AS similitud
    FROM candidatos c
    WHERE c.id_proceso_electoral = p_proceso
      AND c.estado = 'INSCRITO'
      AND (
          c.nombres            ILIKE '%' || p_texto || '%'
          OR c.apellido_paterno ILIKE '%' || p_texto || '%'
          OR c.apellido_materno ILIKE '%' || p_texto || '%'
      )
    ORDER BY similitud DESC
    LIMIT p_limite;
$$;


-- =============================================================
-- 6. TABLA: etl_runs (trazabilidad de ejecuciones del scraper)
-- =============================================================
-- Registro liviano: una fila por ejecución del ETL.
-- No loguea cada candidato — solo el resumen del run.
CREATE TABLE IF NOT EXISTS etl_runs (
    id              SERIAL PRIMARY KEY,
    proceso_id      INTEGER DEFAULT 124,
    inicio          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fin             TIMESTAMPTZ,
    total_scrapeados INTEGER DEFAULT 0,
    total_insertados INTEGER DEFAULT 0,
    total_actualizados INTEGER DEFAULT 0,
    total_errores   INTEGER DEFAULT 0,
    estado          VARCHAR(20) DEFAULT 'CORRIENDO', -- CORRIENDO|OK|ERROR|PARCIAL
    detalle_error   TEXT,
    version_etl     VARCHAR(50),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sin RLS: solo service_role accede (no exponer al frontend)
ALTER TABLE etl_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY etl_runs_service_only ON etl_runs
    FOR ALL USING (auth.role() = 'service_role');

COMMENT ON TABLE etl_runs IS
    'Una fila por ejecución del ETL Python. Trazabilidad sin overhead por candidato.';


-- =============================================================
-- 7. TABLA: etl_errores (log de candidatos fallidos)
-- =============================================================
-- Solo se inserta cuando un candidato específico falla.
-- Permite reintento selectivo sin re-scrapear todo.
CREATE TABLE IF NOT EXISTS etl_errores (
    id              SERIAL PRIMARY KEY,
    etl_run_id      INTEGER REFERENCES etl_runs(id) ON DELETE CASCADE,
    id_hoja_vida    INTEGER,
    url_intentada   TEXT,
    codigo_http     SMALLINT,
    mensaje_error   TEXT,
    intentos        SMALLINT DEFAULT 1,
    resuelto        BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_etl_errores_run
    ON etl_errores(etl_run_id);
CREATE INDEX IF NOT EXISTS idx_etl_errores_pendientes
    ON etl_errores(resuelto) WHERE resuelto = FALSE;

ALTER TABLE etl_errores ENABLE ROW LEVEL SECURITY;
CREATE POLICY etl_errores_service_only ON etl_errores
    FOR ALL USING (auth.role() = 'service_role');

COMMENT ON TABLE etl_errores IS
    'Candidatos que fallaron en scraping. resuelto=FALSE = pendientes de reintento.';


-- =============================================================
-- 8. VERIFICACIÓN FINAL
-- =============================================================
-- Correr esto al final para confirmar que todo se creó bien:
SELECT
    schemaname,
    tablename,
    tableowner
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Verificar triggers
SELECT
    trigger_name,
    event_object_table,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- Verificar índices
SELECT
    indexname,
    tablename,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

