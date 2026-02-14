-- =============================================================
-- VOTO SEGURO 2026 — Script completo unificado
-- Copiar y pegar TODO este contenido en:
-- Supabase Dashboard > SQL Editor > New query > Run
-- =============================================================

-- ─── PARTE 1: SCHEMA ─────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS organizaciones_politicas (
    id_organizacion     INTEGER PRIMARY KEY,
    nombre              VARCHAR(500) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS procesos_electorales (
    id_proceso          INTEGER PRIMARY KEY,
    id_tipo_eleccion    INTEGER NOT NULL,
    descripcion         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO procesos_electorales (id_proceso, id_tipo_eleccion, descripcion)
VALUES (124, 1, 'Elecciones Generales Abril 2026')
ON CONFLICT (id_proceso) DO NOTHING;

CREATE TABLE IF NOT EXISTS candidatos (
    id_hoja_vida                INTEGER PRIMARY KEY,
    id_proceso_electoral        INTEGER REFERENCES procesos_electorales(id_proceso),
    id_organizacion_politica    INTEGER REFERENCES organizaciones_politicas(id_organizacion),
    numero_documento            VARCHAR(20),
    carne_extranjeria           VARCHAR(20),
    nombres                     VARCHAR(300),
    apellido_paterno            VARCHAR(300),
    apellido_materno            VARCHAR(300),
    sexo                        CHAR(1),
    fecha_nacimiento            DATE,
    pais_nacimiento             VARCHAR(100),
    ubigeo_nacimiento           VARCHAR(10),
    departamento_nacimiento     VARCHAR(100),
    provincia_nacimiento        VARCHAR(100),
    distrito_nacimiento         VARCHAR(100),
    ubigeo_domicilio            VARCHAR(10),
    departamento_domicilio      VARCHAR(100),
    provincia_domicilio         VARCHAR(100),
    distrito_domicilio          VARCHAR(100),
    domicilio_direccion         TEXT,
    ubigeo_postula              VARCHAR(10),
    departamento_postula        VARCHAR(100),
    provincia_postula           VARCHAR(100),
    distrito_postula            VARCHAR(100),
    cargo                       VARCHAR(300),
    cargo_otro                  VARCHAR(300),
    numero_candidato            INTEGER,
    id_solicitud_lista          INTEGER,
    estado                      VARCHAR(50),
    tx_guid_foto                VARCHAR(100),
    tx_nombre_archivo           VARCHAR(200),
    tx_nombre_archivo_pdf       VARCHAR(200),
    tx_guid_formato_hv          VARCHAR(100),
    organizacion_politica_nombre VARCHAR(500),
    id_estado_datos_personales  SMALLINT,
    fecha_termino_registro      TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_candidatos_proceso      ON candidatos(id_proceso_electoral);
CREATE INDEX IF NOT EXISTS idx_candidatos_org          ON candidatos(id_organizacion_politica);
CREATE INDEX IF NOT EXISTS idx_candidatos_cargo        ON candidatos(cargo);
CREATE INDEX IF NOT EXISTS idx_candidatos_ubigeo       ON candidatos(ubigeo_postula);
CREATE INDEX IF NOT EXISTS idx_candidatos_nombre_trgm  ON candidatos USING GIN ((nombres || ' ' || apellido_paterno || ' ' || apellido_materno) gin_trgm_ops);

CREATE TABLE IF NOT EXISTS hojas_vida (
    id_hoja_vida            INTEGER PRIMARY KEY REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    data                    JSONB NOT NULL,
    fecha_termino_registro  TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_hojas_vida_gin ON hojas_vida USING GIN (data);

CREATE TABLE IF NOT EXISTS declaracion_ingresos (
    id                       SERIAL PRIMARY KEY,
    id_hoja_vida             INTEGER NOT NULL REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_ingresos           INTEGER,
    anio                     INTEGER,
    remu_bruta_publico       NUMERIC(15,2) DEFAULT 0,
    renta_individual_publico NUMERIC(15,2) DEFAULT 0,
    otro_ingreso_publico     NUMERIC(15,2) DEFAULT 0,
    ingreso_publico          NUMERIC(15,2) GENERATED ALWAYS AS (remu_bruta_publico + renta_individual_publico + otro_ingreso_publico) STORED,
    remu_bruta_privado       NUMERIC(15,2) DEFAULT 0,
    renta_individual_privado NUMERIC(15,2) DEFAULT 0,
    otro_ingreso_privado     NUMERIC(15,2) DEFAULT 0,
    ingreso_privado          NUMERIC(15,2) GENERATED ALWAYS AS (remu_bruta_privado + renta_individual_privado + otro_ingreso_privado) STORED,
    total_ingresos           NUMERIC(15,2),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_ingresos_hv_jne ON declaracion_ingresos(id_hv_ingresos) WHERE id_hv_ingresos IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ingresos_hv ON declaracion_ingresos(id_hoja_vida);

CREATE TABLE IF NOT EXISTS educacion (
    id           SERIAL PRIMARY KEY,
    id_hoja_vida INTEGER NOT NULL REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_edu    INTEGER,
    tipo         VARCHAR(30) NOT NULL,
    institucion  TEXT,
    carrera      TEXT,
    nivel        VARCHAR(100),
    concluido    BOOLEAN,
    anio_egreso  INTEGER,
    anio_titulo  INTEGER,
    tx_comentario TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_educacion_hv   ON educacion(id_hoja_vida);
CREATE INDEX IF NOT EXISTS idx_educacion_tipo ON educacion(tipo);

CREATE TABLE IF NOT EXISTS experiencia_laboral (
    id                SERIAL PRIMARY KEY,
    id_hoja_vida      INTEGER NOT NULL REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_exp_laboral INTEGER,
    centro_trabajo    TEXT,
    ocupacion         TEXT,
    ruc_trabajo       VARCHAR(20),
    direccion         TEXT,
    ubigeo_trabajo    VARCHAR(10),
    pais              VARCHAR(100),
    departamento      VARCHAR(100),
    provincia         VARCHAR(100),
    distrito          VARCHAR(100),
    anio_desde        INTEGER,
    anio_hasta        INTEGER,
    es_actual         BOOLEAN DEFAULT FALSE,
    tx_comentario     TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_exp_laboral_hv ON experiencia_laboral(id_hoja_vida);

CREATE TABLE IF NOT EXISTS trayectoria (
    id                SERIAL PRIMARY KEY,
    id_hoja_vida      INTEGER NOT NULL REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_trayectoria INTEGER,
    tipo              VARCHAR(20) NOT NULL,
    id_organizacion   INTEGER REFERENCES organizaciones_politicas(id_organizacion),
    organizacion_nombre TEXT,
    cargo             VARCHAR(300),
    anio_desde        INTEGER,
    anio_hasta        INTEGER,
    es_actual         BOOLEAN DEFAULT FALSE,
    tx_comentario     TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_trayectoria_hv  ON trayectoria(id_hoja_vida);
CREATE INDEX IF NOT EXISTS idx_trayectoria_tipo ON trayectoria(tipo);
CREATE INDEX IF NOT EXISTS idx_trayectoria_org  ON trayectoria(id_organizacion);

CREATE TABLE IF NOT EXISTS sentencias (
    id              SERIAL PRIMARY KEY,
    id_hoja_vida    INTEGER NOT NULL REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_sentencia INTEGER,
    tipo            VARCHAR(200),
    tiene_sentencia BOOLEAN,
    detalle         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sentencias_hv    ON sentencias(id_hoja_vida);
CREATE INDEX IF NOT EXISTS idx_sentencias_tiene ON sentencias(tiene_sentencia) WHERE tiene_sentencia = TRUE;

CREATE TABLE IF NOT EXISTS bienes_inmuebles (
    id           SERIAL PRIMARY KEY,
    id_hoja_vida INTEGER NOT NULL REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_inmueble INTEGER,
    descripcion  TEXT,
    valor        NUMERIC(15,2),
    ubigeo       VARCHAR(10),
    departamento VARCHAR(100),
    provincia    VARCHAR(100),
    distrito     VARCHAR(100),
    observacion  TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inmuebles_hv ON bienes_inmuebles(id_hoja_vida);

CREATE TABLE IF NOT EXISTS bienes_muebles (
    id           SERIAL PRIMARY KEY,
    id_hoja_vida INTEGER NOT NULL REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_mueble INTEGER,
    tipo_bien    VARCHAR(100),
    marca        VARCHAR(100),
    modelo       VARCHAR(100),
    placa        VARCHAR(20),
    anio         INTEGER,
    valor        NUMERIC(15,2),
    caracteristica TEXT,
    observacion  TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_muebles_hv ON bienes_muebles(id_hoja_vida);

-- ─── PARTE 2: AUDITORÍA ───────────────────────────────────────

CREATE TABLE IF NOT EXISTS audit_log (
    id           BIGSERIAL PRIMARY KEY,
    tabla        VARCHAR(100) NOT NULL,
    operacion    VARCHAR(10)  NOT NULL,
    id_registro  TEXT,
    datos_antes  JSONB,
    datos_despues JSONB,
    usuario_db   TEXT DEFAULT current_user,
    app_fuente   VARCHAR(50),
    ip_origen    INET,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_tabla_op   ON audit_log(tabla, operacion);
CREATE INDEX IF NOT EXISTS idx_audit_created    ON audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_id_registro ON audit_log(id_registro);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS audit_log_service_only ON audit_log;
CREATE POLICY audit_log_service_only ON audit_log FOR ALL USING (auth.role() = 'service_role');

CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id TEXT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id := COALESCE(OLD.id_hoja_vida::TEXT, OLD.id::TEXT);
    ELSE
        v_id := COALESCE(NEW.id_hoja_vida::TEXT, NEW.id::TEXT);
    END IF;
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log(tabla, operacion, id_registro, datos_despues, app_fuente)
        VALUES (TG_TABLE_NAME, 'INSERT', v_id, to_jsonb(NEW), current_setting('app.fuente', true));
    ELSIF TG_OP = 'UPDATE' THEN
        IF (to_jsonb(NEW) - 'updated_at') <> (to_jsonb(OLD) - 'updated_at') THEN
            INSERT INTO audit_log(tabla, operacion, id_registro, datos_antes, datos_despues, app_fuente)
            VALUES (TG_TABLE_NAME, 'UPDATE', v_id, to_jsonb(OLD), to_jsonb(NEW), current_setting('app.fuente', true));
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log(tabla, operacion, id_registro, datos_antes, app_fuente)
        VALUES (TG_TABLE_NAME, 'DELETE', v_id, to_jsonb(OLD), current_setting('app.fuente', true));
    END IF;
    RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_audit_candidatos     ON candidatos;
DROP TRIGGER IF EXISTS trg_audit_hojas_vida     ON hojas_vida;
DROP TRIGGER IF EXISTS trg_audit_org_pol        ON organizaciones_politicas;
DROP TRIGGER IF EXISTS trg_updated_at_candidatos ON candidatos;
DROP TRIGGER IF EXISTS trg_updated_at_hojas_vida ON hojas_vida;
DROP TRIGGER IF EXISTS trg_updated_at_org_pol   ON organizaciones_politicas;

CREATE TRIGGER trg_audit_candidatos     AFTER INSERT OR UPDATE OR DELETE ON candidatos          FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();
CREATE TRIGGER trg_audit_hojas_vida     AFTER INSERT OR UPDATE OR DELETE ON hojas_vida           FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();
CREATE TRIGGER trg_audit_org_pol        AFTER INSERT OR UPDATE OR DELETE ON organizaciones_politicas FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();
CREATE TRIGGER trg_updated_at_candidatos BEFORE UPDATE ON candidatos                             FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_updated_at_hojas_vida BEFORE UPDATE ON hojas_vida                             FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_updated_at_org_pol   BEFORE UPDATE ON organizaciones_politicas                FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ─── PARTE 3: RLS + VISTAS + UTILIDADES ──────────────────────

ALTER TABLE organizaciones_politicas  ENABLE ROW LEVEL SECURITY;
ALTER TABLE procesos_electorales      ENABLE ROW LEVEL SECURITY;
ALTER TABLE candidatos                ENABLE ROW LEVEL SECURITY;
ALTER TABLE hojas_vida                ENABLE ROW LEVEL SECURITY;
ALTER TABLE declaracion_ingresos      ENABLE ROW LEVEL SECURITY;
ALTER TABLE educacion                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE experiencia_laboral       ENABLE ROW LEVEL SECURITY;
ALTER TABLE trayectoria               ENABLE ROW LEVEL SECURITY;
ALTER TABLE sentencias                ENABLE ROW LEVEL SECURITY;
ALTER TABLE bienes_inmuebles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE bienes_muebles            ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS lectura_publica ON organizaciones_politicas;
DROP POLICY IF EXISTS lectura_publica ON procesos_electorales;
DROP POLICY IF EXISTS lectura_publica ON candidatos;
DROP POLICY IF EXISTS lectura_publica ON hojas_vida;
DROP POLICY IF EXISTS lectura_publica ON declaracion_ingresos;
DROP POLICY IF EXISTS lectura_publica ON educacion;
DROP POLICY IF EXISTS lectura_publica ON experiencia_laboral;
DROP POLICY IF EXISTS lectura_publica ON trayectoria;
DROP POLICY IF EXISTS lectura_publica ON sentencias;
DROP POLICY IF EXISTS lectura_publica ON bienes_inmuebles;
DROP POLICY IF EXISTS lectura_publica ON bienes_muebles;

CREATE POLICY lectura_publica ON organizaciones_politicas FOR SELECT USING (true);
CREATE POLICY lectura_publica ON procesos_electorales     FOR SELECT USING (true);
CREATE POLICY lectura_publica ON candidatos               FOR SELECT USING (true);
CREATE POLICY lectura_publica ON hojas_vida               FOR SELECT USING (true);
CREATE POLICY lectura_publica ON declaracion_ingresos     FOR SELECT USING (true);
CREATE POLICY lectura_publica ON educacion                FOR SELECT USING (true);
CREATE POLICY lectura_publica ON experiencia_laboral      FOR SELECT USING (true);
CREATE POLICY lectura_publica ON trayectoria              FOR SELECT USING (true);
CREATE POLICY lectura_publica ON sentencias               FOR SELECT USING (true);
CREATE POLICY lectura_publica ON bienes_inmuebles         FOR SELECT USING (true);
CREATE POLICY lectura_publica ON bienes_muebles           FOR SELECT USING (true);

CREATE OR REPLACE VIEW candidatos_resumen AS
SELECT
    c.id_hoja_vida,
    c.id_proceso_electoral,
    c.id_organizacion_politica,
    c.organizacion_politica_nombre,
    c.nombres,
    c.apellido_paterno,
    c.apellido_materno,
    TRIM(c.apellido_paterno || ' ' || c.apellido_materno || ', ' || c.nombres) AS nombre_completo,
    c.sexo,
    c.cargo,
    c.numero_candidato,
    c.ubigeo_postula,
    c.departamento_postula,
    c.provincia_postula,
    c.distrito_postula,
    c.estado,
    CASE WHEN c.tx_guid_foto IS NOT NULL
         THEN 'https://declara.jne.gob.pe/ASSETS/FOTOCANDIDATO/' || c.tx_nombre_archivo
         ELSE NULL END AS url_foto,
    c.fecha_termino_registro
FROM candidatos c
WHERE c.estado = 'INSCRITO';

-- ─── PARTE 4: VOTOS ANÓNIMOS ─────────────────────────────────

CREATE TABLE IF NOT EXISTS sesiones (
    id            BIGSERIAL PRIMARY KEY,
    session_token VARCHAR(36) NOT NULL UNIQUE,
    pais          VARCHAR(5),
    region        VARCHAR(100),
    es_movil      BOOLEAN,
    utm_source    VARCHAR(100),
    utm_medium    VARCHAR(100),
    utm_campaign  VARCHAR(100),
    referrer      VARCHAR(500),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sesiones_token   ON sesiones(session_token);
CREATE INDEX IF NOT EXISTS idx_sesiones_created ON sesiones(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sesiones_region  ON sesiones(pais, region);

ALTER TABLE sesiones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sesiones_insert_anonimo ON sesiones;
DROP POLICY IF EXISTS sesiones_select_service ON sesiones;
CREATE POLICY sesiones_insert_anonimo ON sesiones FOR INSERT WITH CHECK (true);
CREATE POLICY sesiones_select_service ON sesiones FOR SELECT USING (auth.role() = 'service_role');

CREATE TABLE IF NOT EXISTS intenciones_voto (
    id                       BIGSERIAL PRIMARY KEY,
    session_token            VARCHAR(36) NOT NULL REFERENCES sesiones(session_token) ON DELETE CASCADE,
    tipo_cargo               VARCHAR(50) NOT NULL,
    id_organizacion_politica INTEGER,
    nombre_organizacion      VARCHAR(500),
    id_preferencial_1        INTEGER,
    id_preferencial_2        INTEGER,
    es_voto_blanco           BOOLEAN NOT NULL DEFAULT FALSE,
    es_voto_nulo             BOOLEAN NOT NULL DEFAULT FALSE,
    es_voto_valido           BOOLEAN NOT NULL DEFAULT FALSE,
    ubigeo_sesion            VARCHAR(10),
    departamento_sesion      VARCHAR(100),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_iv_session       ON intenciones_voto(session_token);
CREATE INDEX IF NOT EXISTS idx_iv_cargo         ON intenciones_voto(tipo_cargo);
CREATE INDEX IF NOT EXISTS idx_iv_org           ON intenciones_voto(id_organizacion_politica) WHERE id_organizacion_politica IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_iv_created       ON intenciones_voto(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_iv_cargo_org_dep ON intenciones_voto(tipo_cargo, nombre_organizacion, departamento_sesion);

ALTER TABLE intenciones_voto ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS iv_insert_anonimo ON intenciones_voto;
DROP POLICY IF EXISTS iv_select_service ON intenciones_voto;
CREATE POLICY iv_insert_anonimo ON intenciones_voto FOR INSERT WITH CHECK (true);
CREATE POLICY iv_select_service ON intenciones_voto FOR SELECT USING (auth.role() = 'service_role');

-- ETL runs & errores
CREATE TABLE IF NOT EXISTS etl_runs (
    id                 SERIAL PRIMARY KEY,
    proceso_id         INTEGER DEFAULT 124,
    inicio             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fin                TIMESTAMPTZ,
    total_scrapeados   INTEGER DEFAULT 0,
    total_insertados   INTEGER DEFAULT 0,
    total_actualizados INTEGER DEFAULT 0,
    total_errores      INTEGER DEFAULT 0,
    estado             VARCHAR(20) DEFAULT 'CORRIENDO',
    detalle_error      TEXT,
    version_etl        VARCHAR(50),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE etl_runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS etl_runs_service_only ON etl_runs;
CREATE POLICY etl_runs_service_only ON etl_runs FOR ALL USING (auth.role() = 'service_role');

CREATE TABLE IF NOT EXISTS etl_errores (
    id             SERIAL PRIMARY KEY,
    etl_run_id     INTEGER REFERENCES etl_runs(id) ON DELETE CASCADE,
    id_hoja_vida   INTEGER,
    url_intentada  TEXT,
    codigo_http    SMALLINT,
    mensaje_error  TEXT,
    intentos       SMALLINT DEFAULT 1,
    resuelto       BOOLEAN DEFAULT FALSE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_etl_errores_run        ON etl_errores(etl_run_id);
CREATE INDEX IF NOT EXISTS idx_etl_errores_pendientes ON etl_errores(resuelto) WHERE resuelto = FALSE;
ALTER TABLE etl_errores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS etl_errores_service_only ON etl_errores;
CREATE POLICY etl_errores_service_only ON etl_errores FOR ALL USING (auth.role() = 'service_role');

-- ─── VERIFICACIÓN FINAL ───────────────────────────────────────
SELECT tablename, (SELECT count(*) FROM information_schema.columns WHERE table_name = t.tablename) AS columnas
FROM pg_tables t
WHERE schemaname = 'public'
ORDER BY tablename;
