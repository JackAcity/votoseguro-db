-- =============================================================
-- VOTO SEGURO 2026 — Captura anónima de intención de voto
-- Sin PII, sin cookies, sin auth obligatoria
-- Cumple Ley 29733 (Perú) + GDPR principio minimización
-- =============================================================

-- =============================================================
-- 1. SESIONES ANÓNIMAS
-- =============================================================
-- Una sesión = una visita al simulador.
-- session_token: generado en el browser (crypto.randomUUID()),
-- nunca vinculado a una identidad real.
CREATE TABLE IF NOT EXISTS sesiones (
    id              BIGSERIAL PRIMARY KEY,
    session_token   VARCHAR(36) NOT NULL UNIQUE,  -- UUID v4 del browser
    -- Geo aproximada (país/depto — NUNCA ciudad exacta ni IP)
    pais            VARCHAR(5),    -- 'PE', 'US', etc.
    region          VARCHAR(100),  -- 'Lima', 'Arequipa', etc.
    -- Dispositivo (sin fingerprint)
    es_movil        BOOLEAN,
    -- Fuente de tráfico
    utm_source      VARCHAR(100),  -- 'whatsapp', 'google', 'direct', etc.
    utm_medium      VARCHAR(100),
    utm_campaign    VARCHAR(100),
    referrer        VARCHAR(500),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sesiones_token
    ON sesiones(session_token);
CREATE INDEX IF NOT EXISTS idx_sesiones_created
    ON sesiones(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sesiones_region
    ON sesiones(pais, region);

-- RLS: anon puede INSERT su propia sesión, no puede leer otras
ALTER TABLE sesiones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sesiones_insert_anonimo" ON sesiones
    FOR INSERT WITH CHECK (true);

-- Solo service_role puede leer todas las sesiones (dashboard analytics)
CREATE POLICY "sesiones_select_service" ON sesiones
    FOR SELECT USING (auth.role() = 'service_role');


-- =============================================================
-- 2. INTENCIONES DE VOTO
-- =============================================================
-- Una fila por columna electoral marcada en el simulador.
-- 5 columnas = hasta 5 filas por sesión.
-- id_organizacion_politica: FK a org real (cuando tengamos data JNE)
--   o nombre textual del mock mientras tanto.
CREATE TABLE IF NOT EXISTS intenciones_voto (
    id                          BIGSERIAL PRIMARY KEY,
    session_token               VARCHAR(36) NOT NULL
                                REFERENCES sesiones(session_token) ON DELETE CASCADE,
    -- Columna electoral
    tipo_cargo                  VARCHAR(50) NOT NULL,
    -- 'FORMULA_PRESIDENCIAL' | 'SENADOR_NACIONAL' | 'SENADOR_REGIONAL'
    -- | 'DIPUTADO' | 'PARLAMENTO_ANDINO'

    -- Organización elegida
    id_organizacion_politica    INTEGER,   -- NULL hasta que llegue data real
    nombre_organizacion         VARCHAR(500), -- siempre presente (mock o real)

    -- Voto preferencial (opcional)
    id_preferencial_1           INTEGER,   -- id_hoja_vida JNE o NULL
    id_preferencial_2           INTEGER,   -- solo para cargos con max 2 prefs

    -- Estado del voto en esa columna
    es_voto_blanco              BOOLEAN NOT NULL DEFAULT FALSE,
    es_voto_nulo                BOOLEAN NOT NULL DEFAULT FALSE,
    es_voto_valido              BOOLEAN NOT NULL DEFAULT FALSE,

    -- Ubigeo donde simula (para ranking regional — clave para B2B)
    ubigeo_sesion               VARCHAR(10),
    departamento_sesion         VARCHAR(100),

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_iv_session
    ON intenciones_voto(session_token);
CREATE INDEX IF NOT EXISTS idx_iv_cargo
    ON intenciones_voto(tipo_cargo);
CREATE INDEX IF NOT EXISTS idx_iv_org
    ON intenciones_voto(id_organizacion_politica)
    WHERE id_organizacion_politica IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_iv_created
    ON intenciones_voto(created_at DESC);
-- Índice para ranking regional (query más frecuente del dashboard)
CREATE INDEX IF NOT EXISTS idx_iv_cargo_org_ubigeo
    ON intenciones_voto(tipo_cargo, nombre_organizacion, departamento_sesion);

-- RLS: anon puede INSERT, no leer
ALTER TABLE intenciones_voto ENABLE ROW LEVEL SECURITY;

CREATE POLICY "iv_insert_anonimo" ON intenciones_voto
    FOR INSERT WITH CHECK (true);

CREATE POLICY "iv_select_service" ON intenciones_voto
    FOR SELECT USING (auth.role() = 'service_role');


-- =============================================================
-- 3. VISTA: ranking_por_cargo
-- =============================================================
-- Top organizaciones por intención de voto, por cargo.
-- Esta es la vista que alimenta el dashboard B2B futuro.
-- SECURITY DEFINER: corre con permisos del dueño, no del caller.
CREATE OR REPLACE VIEW ranking_intenciones AS
SELECT
    tipo_cargo,
    nombre_organizacion,
    departamento_sesion,
    COUNT(*)                            AS total_votos,
    COUNT(*) FILTER (WHERE es_voto_valido)  AS votos_validos,
    COUNT(*) FILTER (WHERE es_voto_blanco)  AS votos_blancos,
    COUNT(*) FILTER (WHERE es_voto_nulo)    AS votos_nulos,
    DATE_TRUNC('day', created_at)       AS dia
FROM intenciones_voto
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY tipo_cargo, nombre_organizacion, departamento_sesion,
         DATE_TRUNC('day', created_at)
ORDER BY total_votos DESC;

-- Solo service_role accede al ranking (datos sensibles para B2B)
-- El frontend público NO ve esta vista directamente

