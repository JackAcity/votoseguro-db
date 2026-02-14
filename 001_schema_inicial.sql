-- =============================================================
-- VOTO SEGURO 2026 — Schema inicial
-- Supabase (PostgreSQL 15) — optimizado Free Tier
-- Autor: Arquitecto Voto Seguro
-- Versión: 1.0.0
-- Ejecutar en orden: 001 → 002 → 003
-- =============================================================

-- -------------------------------------------------------------
-- EXTENSIONES (solo las necesarias)
-- -------------------------------------------------------------
-- pg_trgm: búsqueda por nombre de candidato (ILIKE optimizado)
-- NO instalar uuid-ossp ni postgis aún (consumen recursos)
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- =============================================================
-- 1. ORGANIZACIONES POLÍTICAS
-- =============================================================
CREATE TABLE IF NOT EXISTS organizaciones_politicas (
    id_organizacion     INTEGER PRIMARY KEY,
    nombre              VARCHAR(500) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE organizaciones_politicas IS
    'Partidos y alianzas electorales. Fuente: JNE API campo idOrganizacionPolitica.';


-- =============================================================
-- 2. PROCESOS ELECTORALES
-- =============================================================
CREATE TABLE IF NOT EXISTS procesos_electorales (
    id_proceso          INTEGER PRIMARY KEY,
    id_tipo_eleccion    INTEGER NOT NULL,
    descripcion         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insertar proceso 124 directamente (Elecciones Generales Abril 2026)
INSERT INTO procesos_electorales (id_proceso, id_tipo_eleccion, descripcion)
VALUES (124, 1, 'Elecciones Generales Abril 2026')
ON CONFLICT (id_proceso) DO NOTHING;

COMMENT ON TABLE procesos_electorales IS
    'Proceso electoral activo: id_proceso=124, Elecciones Generales Abril 2026.';


-- =============================================================
-- 3. CANDIDATOS (tabla principal)
-- =============================================================
CREATE TABLE IF NOT EXISTS candidatos (
    -- PK
    id_hoja_vida                INTEGER PRIMARY KEY,

    -- FKs
    id_proceso_electoral        INTEGER REFERENCES procesos_electorales(id_proceso),
    id_organizacion_politica    INTEGER REFERENCES organizaciones_politicas(id_organizacion),

    -- Identidad
    numero_documento            VARCHAR(20),
    carne_extranjeria           VARCHAR(20),

    -- Nombre
    nombres                     VARCHAR(300),
    apellido_paterno            VARCHAR(300),
    apellido_materno            VARCHAR(300),

    -- Datos personales
    sexo                        CHAR(1),          -- '1'=M '2'=F según JNE
    fecha_nacimiento            DATE,
    pais_nacimiento             VARCHAR(100),

    -- Nacimiento
    ubigeo_nacimiento           VARCHAR(10),
    departamento_nacimiento     VARCHAR(100),
    provincia_nacimiento        VARCHAR(100),
    distrito_nacimiento         VARCHAR(100),

    -- Domicilio
    ubigeo_domicilio            VARCHAR(10),
    departamento_domicilio      VARCHAR(100),
    provincia_domicilio         VARCHAR(100),
    distrito_domicilio          VARCHAR(100),
    domicilio_direccion         TEXT,             -- JNE devuelve '*** *** ***' enmascarado

    -- Distrito donde postula
    ubigeo_postula              VARCHAR(10),
    departamento_postula        VARCHAR(100),
    provincia_postula           VARCHAR(100),
    distrito_postula            VARCHAR(100),

    -- Cargo electoral
    cargo                       VARCHAR(300),
    cargo_otro                  VARCHAR(300),
    numero_candidato            INTEGER,
    id_solicitud_lista          INTEGER,
    estado                      VARCHAR(50),

    -- Foto (CRÍTICO para mostrar en app)
    -- URL foto: https://declara.jne.gob.pe/ASSETS/FOTOCANDIDATO/{tx_guid_foto}
    tx_guid_foto                VARCHAR(100),     -- ej: '251cd1c0-acc7-4338-bd8a-439ccb9238d0'
    tx_nombre_archivo           VARCHAR(200),     -- ej: '251cd1c0-...jpeg'
    tx_nombre_archivo_pdf       VARCHAR(200),     -- PDF hoja de vida
    tx_guid_formato_hv          VARCHAR(100),     -- PDF firmado

    -- Nombre textual org (desnormalizado para queries rápidas sin JOIN)
    organizacion_politica_nombre VARCHAR(500),

    -- Estado interno JNE
    id_estado_datos_personales  SMALLINT,

    -- Auditoría
    fecha_termino_registro      TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices — solo los que realmente se van a usar en queries
CREATE INDEX IF NOT EXISTS idx_candidatos_proceso
    ON candidatos(id_proceso_electoral);

CREATE INDEX IF NOT EXISTS idx_candidatos_org
    ON candidatos(id_organizacion_politica);

CREATE INDEX IF NOT EXISTS idx_candidatos_cargo
    ON candidatos(cargo);

CREATE INDEX IF NOT EXISTS idx_candidatos_ubigeo_postula
    ON candidatos(ubigeo_postula);

-- Búsqueda por nombre (trigram — requiere pg_trgm)
CREATE INDEX IF NOT EXISTS idx_candidatos_nombre_trgm
    ON candidatos USING GIN (
        (nombres || ' ' || apellido_paterno || ' ' || apellido_materno) gin_trgm_ops
    );

COMMENT ON TABLE candidatos IS
    'Un candidato = una hoja de vida JNE. PK = idHojaVida de la API.';
COMMENT ON COLUMN candidatos.tx_guid_foto IS
    'GUID para construir URL de foto: https://declara.jne.gob.pe/ASSETS/FOTOCANDIDATO/{guid}';
COMMENT ON COLUMN candidatos.sexo IS
    'Codificado por JNE: 1=Masculino, 2=Femenino (string en API, guardamos CHAR)';


-- =============================================================
-- 4. HOJAS DE VIDA (JSON raw — fuente de verdad)
-- =============================================================
-- Estrategia: guardar el JSON completo de la JNE aquí.
-- Si falta alguna columna en las tablas estructuradas,
-- siempre se puede hacer SELECT data->>'campo' FROM hojas_vida.
CREATE TABLE IF NOT EXISTS hojas_vida (
    id_hoja_vida            INTEGER PRIMARY KEY
                            REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    data                    JSONB NOT NULL,
    fecha_termino_registro  TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- GIN sobre JSONB — permite queries como data @> '{"cargo":"PRESIDENTE"}'
CREATE INDEX IF NOT EXISTS idx_hojas_vida_gin
    ON hojas_vida USING GIN (data);

COMMENT ON TABLE hojas_vida IS
    'JSON raw de la JNE. Source of truth. Las tablas de detalle son vistas materializadas de esto.';


-- =============================================================
-- 5. DECLARACIÓN DE INGRESOS
-- =============================================================
CREATE TABLE IF NOT EXISTS declaracion_ingresos (
    id                      SERIAL PRIMARY KEY,
    id_hoja_vida            INTEGER NOT NULL
                            REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_ingresos          INTEGER,          -- ID propio JNE (para upsert sin duplicados)
    anio                    INTEGER,
    -- Ingresos públicos desglosados (como los devuelve la API)
    remu_bruta_publico      NUMERIC(15,2) DEFAULT 0,
    renta_individual_publico NUMERIC(15,2) DEFAULT 0,
    otro_ingreso_publico    NUMERIC(15,2) DEFAULT 0,
    ingreso_publico         NUMERIC(15,2)     -- total público (suma de 3 anteriores)
                            GENERATED ALWAYS AS
                            (remu_bruta_publico + renta_individual_publico + otro_ingreso_publico)
                            STORED,
    -- Ingresos privados desglosados
    remu_bruta_privado      NUMERIC(15,2) DEFAULT 0,
    renta_individual_privado NUMERIC(15,2) DEFAULT 0,
    otro_ingreso_privado    NUMERIC(15,2) DEFAULT 0,
    ingreso_privado         NUMERIC(15,2)
                            GENERATED ALWAYS AS
                            (remu_bruta_privado + renta_individual_privado + otro_ingreso_privado)
                            STORED,
    total_ingresos          NUMERIC(15,2),    -- total reportado por JNE
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ingresos_hv_jne
    ON declaracion_ingresos(id_hv_ingresos) WHERE id_hv_ingresos IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ingresos_hv
    ON declaracion_ingresos(id_hoja_vida);


-- =============================================================
-- 6. EDUCACIÓN
-- =============================================================
-- La API tiene 5 sub-tipos de educación. Los colapsamos en una
-- tabla con columna 'tipo' como discriminador.
CREATE TABLE IF NOT EXISTS educacion (
    id              SERIAL PRIMARY KEY,
    id_hoja_vida    INTEGER NOT NULL
                    REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_edu       INTEGER,      -- ID propio JNE por sub-tipo
    -- Tipo discriminador: BASICA | TECNICO | NO_UNIVERSITARIA | UNIVERSITARIA | POSGRADO
    tipo            VARCHAR(30) NOT NULL,
    institucion     TEXT,
    carrera         TEXT,
    nivel           VARCHAR(100), -- bachiller, título, maestría, doctorado
    concluido       BOOLEAN,
    anio_egreso     INTEGER,
    anio_titulo     INTEGER,
    tx_comentario   TEXT,         -- notas del JNE (ej: "título reconocido el...")
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_educacion_hv ON educacion(id_hoja_vida);
CREATE INDEX IF NOT EXISTS idx_educacion_tipo ON educacion(tipo);


-- =============================================================
-- 7. EXPERIENCIA LABORAL
-- =============================================================
CREATE TABLE IF NOT EXISTS experiencia_laboral (
    id                  SERIAL PRIMARY KEY,
    id_hoja_vida        INTEGER NOT NULL
                        REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_exp_laboral   INTEGER,      -- ID propio JNE (para upsert)
    centro_trabajo      TEXT,
    ocupacion           TEXT,
    ruc_trabajo         VARCHAR(20),  -- RUC empresa (si existe)
    direccion           TEXT,
    ubigeo_trabajo      VARCHAR(10),
    pais                VARCHAR(100),
    departamento        VARCHAR(100),
    provincia           VARCHAR(100),
    distrito            VARCHAR(100),
    anio_desde          INTEGER,
    -- anio_hasta: NULL = "hasta la actualidad" (API devuelve texto)
    anio_hasta          INTEGER,
    es_actual           BOOLEAN DEFAULT FALSE, -- TRUE si anioHasta = 'HASTA LA ACTUALIDAD'
    tx_comentario       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exp_laboral_hv ON experiencia_laboral(id_hoja_vida);


-- =============================================================
-- 8. TRAYECTORIA POLÍTICA
-- =============================================================
-- API tiene cargoPartidario + cargoEleccion → colapsado con tipo
CREATE TABLE IF NOT EXISTS trayectoria (
    id                  SERIAL PRIMARY KEY,
    id_hoja_vida        INTEGER NOT NULL
                        REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_trayectoria   INTEGER,          -- ID propio JNE
    tipo                VARCHAR(20) NOT NULL, -- 'PARTIDARIO' | 'ELECCION'
    id_organizacion     INTEGER
                        REFERENCES organizaciones_politicas(id_organizacion),
    organizacion_nombre TEXT,             -- desnormalizado para queries rápidas
    cargo               VARCHAR(300),
    anio_desde          INTEGER,
    anio_hasta          INTEGER,
    es_actual           BOOLEAN DEFAULT FALSE,
    tx_comentario       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trayectoria_hv   ON trayectoria(id_hoja_vida);
CREATE INDEX IF NOT EXISTS idx_trayectoria_tipo  ON trayectoria(tipo);
CREATE INDEX IF NOT EXISTS idx_trayectoria_org   ON trayectoria(id_organizacion);


-- =============================================================
-- 9. SENTENCIAS
-- =============================================================
CREATE TABLE IF NOT EXISTS sentencias (
    id              SERIAL PRIMARY KEY,
    id_hoja_vida    INTEGER NOT NULL
                    REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_sentencia INTEGER,
    tipo            VARCHAR(200),    -- 'PENAL' | 'OBLIGACIONES_ALIMENTARIAS'
    tiene_sentencia BOOLEAN,
    detalle         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sentencias_hv    ON sentencias(id_hoja_vida);
CREATE INDEX IF NOT EXISTS idx_sentencias_tiene ON sentencias(tiene_sentencia)
    WHERE tiene_sentencia = TRUE;   -- índice parcial: solo candidatos CON sentencias


-- =============================================================
-- 10. BIENES INMUEBLES (transparencia patrimonial)
-- =============================================================
CREATE TABLE IF NOT EXISTS bienes_inmuebles (
    id              SERIAL PRIMARY KEY,
    id_hoja_vida    INTEGER NOT NULL
                    REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_inmueble  INTEGER,
    descripcion     TEXT,
    valor           NUMERIC(15,2),
    ubigeo          VARCHAR(10),
    departamento    VARCHAR(100),
    provincia       VARCHAR(100),
    distrito        VARCHAR(100),
    observacion     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inmuebles_hv ON bienes_inmuebles(id_hoja_vida);


-- =============================================================
-- 11. BIENES MUEBLES (vehículos y otros)
-- =============================================================
CREATE TABLE IF NOT EXISTS bienes_muebles (
    id              SERIAL PRIMARY KEY,
    id_hoja_vida    INTEGER NOT NULL
                    REFERENCES candidatos(id_hoja_vida) ON DELETE CASCADE,
    id_hv_mueble    INTEGER,
    tipo_bien       VARCHAR(100),    -- 'REGISTRO DE PROPIEDAD VEHICULAR', etc.
    marca           VARCHAR(100),
    modelo          VARCHAR(100),
    placa           VARCHAR(20),
    anio            INTEGER,
    valor           NUMERIC(15,2),
    caracteristica  TEXT,
    observacion     TEXT,            -- ej: "embargado", "comprado en 2017"
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_muebles_hv ON bienes_muebles(id_hoja_vida);

