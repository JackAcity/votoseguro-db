-- =============================================================
-- FIX: fn_audit_trigger — soportar PKs distintas por tabla
-- Problema: COALESCE(NEW.id_hoja_vida, NEW.id) falla en
--           organizaciones_politicas que tiene PK "id_organizacion"
-- Solución: usar TG_TABLE_NAME para obtener la PK correcta
-- =============================================================

CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id TEXT;
    v_row JSONB;
BEGIN
    -- Obtener la fila como JSONB para extraer la PK por nombre de campo
    IF TG_OP = 'DELETE' THEN
        v_row := to_jsonb(OLD);
    ELSE
        v_row := to_jsonb(NEW);
    END IF;

    -- Obtener PK según la tabla
    CASE TG_TABLE_NAME
        WHEN 'candidatos'              THEN v_id := (v_row->>'id_hoja_vida');
        WHEN 'hojas_vida'              THEN v_id := (v_row->>'id_hoja_vida');
        WHEN 'organizaciones_politicas' THEN v_id := (v_row->>'id_organizacion');
        WHEN 'procesos_electorales'    THEN v_id := (v_row->>'id_proceso');
        WHEN 'sesiones'                THEN v_id := (v_row->>'id');
        WHEN 'intenciones_voto'        THEN v_id := (v_row->>'id');
        ELSE v_id := COALESCE(
            v_row->>'id_hoja_vida',
            v_row->>'id_organizacion',
            v_row->>'id',
            '?'
        );
    END CASE;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log(tabla, operacion, id_registro, datos_despues, app_fuente)
        VALUES (
            TG_TABLE_NAME,
            'INSERT',
            v_id,
            to_jsonb(NEW),
            current_setting('app.fuente', true)
        );

    ELSIF TG_OP = 'UPDATE' THEN
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
