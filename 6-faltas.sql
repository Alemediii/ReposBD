-----------------------------------------------------------------------
-- 6-faltas.sql
-- Datos de prueba para tablas vacías: AULA, EXAMEN, 
-- EXAMEN_ES_MATERIA, ASISTENCIA, VIGILA, ANE
-----------------------------------------------------------------------

SET DEFINE OFF;
SET SERVEROUTPUT ON;

-----------------------------------------------------------------------
-- 1. AULAS
-----------------------------------------------------------------------

-- Se reutiliza el procedimiento de entrega1 (debe existir)
EXEC PR_BORRA_AULAS;
EXEC PR_RELLENA_AULAS(20, 100);

-----------------------------------------------------------------------
-- 2. EXAMENES, ASISTENCIA, VIGILA, ANE
-----------------------------------------------------------------------

CREATE OR REPLACE PACKAGE PK_GENERA_FALTANTES AS
    PROCEDURE PR_GENERAR;
END PK_GENERA_FALTANTES;
/

CREATE OR REPLACE PACKAGE BODY PK_GENERA_FALTANTES AS

    PROCEDURE PR_GENERAR AS
        TYPE t_materias_cod IS TABLE OF materia.codigo%TYPE;
        v_materias t_materias_cod;
        v_fecha_inicio DATE := TO_DATE('09/06/2026 09:00', 'DD/MM/YYYY HH24:MI');
        v_fecha_actual DATE;
        v_aula_disponible INTEGER;
        v_sede_asignada INTEGER;
        v_vocal_dni vocal.dni%TYPE;
        v_idx INTEGER;
        v_total_materias INTEGER;
    BEGIN
        -- Obtener lista de materias
        SELECT codigo BULK COLLECT INTO v_materias FROM materia ORDER BY codigo;
        v_total_materias := v_materias.COUNT;

        DBMS_OUTPUT.PUT_LINE('Generando datos para ' || v_total_materias || ' materias...');

        -- Recorrer cada materia y crear un examen
        FOR i IN 1..v_total_materias LOOP
            -- Cada materia tiene examen en un horario escalonado (4 examenes por dia, 2 franjas)
            v_fecha_actual := v_fecha_inicio + FLOOR((i-1) / 4);  -- 4 examenes por dia
            v_fecha_actual := v_fecha_actual + MOD(((i-1) * 2), 8) / 24; -- separados 2h

            FOR r_sede IN (SELECT codigo FROM sede ORDER BY codigo) LOOP
                -- Buscar un aula libre en esta sede para este horario
                BEGIN
                    SELECT a.codigo INTO v_aula_disponible
                    FROM aula a
                    WHERE a.sede_codigo = r_sede.codigo
                      AND NOT EXISTS (
                          SELECT 1 FROM examen e
                          WHERE e.aula_codigo = a.codigo
                            AND e.aula_sede_codigo = a.sede_codigo
                            AND e.fechayhora = v_fecha_actual
                      )
                      AND ROWNUM = 1;

                    -- Elegir un vocal disponible (que no esté ya vigilando en ese horario)
                    SELECT dni INTO v_vocal_dni
                    FROM vocal
                    WHERE NOT EXISTS (
                        SELECT 1 FROM vigila v
                        WHERE v.vocal_dni = vocal.dni
                          AND v.examen_fechayhora = v_fecha_actual
                    )
                    AND ROWNUM = 1;

                    -- Insertar EXAMEN
                    INSERT INTO examen (fechayhora, vocal_dni, aula_codigo, aula_sede_codigo)
                    VALUES (v_fecha_actual, v_vocal_dni, v_aula_disponible, r_sede.codigo);

                    -- Insertar EXAMEN_ES_MATERIA
                    INSERT INTO examen_es_materia (materia_codigo, examen_fechayhora, examen_aula_codigo, examen_sede_codigo)
                    VALUES (v_materias(i), v_fecha_actual, v_aula_disponible, r_sede.codigo);

                    -- Insertar VIGILA
                    INSERT INTO vigila (vocal_dni, examen_fechayhora, examen_aula_codigo, examen_sede_codigo)
                    VALUES (v_vocal_dni, v_fecha_actual, v_aula_disponible, r_sede.codigo);

                    -- Asignar estudiantes al examen (los matriculados en esta materia cuyo centro esté en esta sede)
                    INSERT INTO asistencia (asiste, entrega, examen_fechayhora, examen_aula_codigo, examen_sede_codigo, materia_codigo, estudiante_dni)
                    SELECT 
                        'S', 'S', 
                        v_fecha_actual, v_aula_disponible, r_sede.codigo, 
                        v_materias(i), mt.estudiante_dni
                    FROM matriculado mt
                    JOIN estudiante e ON e.dni = mt.estudiante_dni
                    JOIN centro c ON c.codigo = e.centro_codigo
                    WHERE mt.materia_codigo = v_materias(i)
                      AND c.sede_codigo = r_sede.codigo;

                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        NULL; -- No hay aula/vocal libre en esta sede para este horario, se salta
                END;
            END LOOP;
        END LOOP;

        -- Crear algunos registros ANE (alumnos con necesidades especiales)
        INSERT INTO ane (dni, descabezar, aulaaparte)
        SELECT dni, 'S', 'N' FROM (
            SELECT dni FROM estudiante SAMPLE(1)
        ) WHERE ROWNUM <= 10;

        INSERT INTO ane (dni, descabezar, aulaaparte)
        SELECT dni, 'N', 'S' FROM (
            SELECT dni FROM estudiante SAMPLE(1)
            WHERE dni NOT IN (SELECT dni FROM ane)
        ) WHERE ROWNUM <= 5;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Datos generados correctamente.');

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
            RAISE;
    END PR_GENERAR;

END PK_GENERA_FALTANTES;
/

BEGIN
    PK_GENERA_FALTANTES.PR_GENERAR;
END;
/

-----------------------------------------------------------------------
-- Verificación
-----------------------------------------------------------------------

SELECT 'AULAS' as tabla, COUNT(*) as filas FROM aula UNION ALL
SELECT 'EXAMEN', COUNT(*) FROM examen UNION ALL
SELECT 'EXAMEN_ES_MATERIA', COUNT(*) FROM examen_es_materia UNION ALL
SELECT 'ASISTENCIA', COUNT(*) FROM asistencia UNION ALL
SELECT 'VIGILA', COUNT(*) FROM vigila UNION ALL
SELECT 'ANE', COUNT(*) FROM ane;

DROP PACKAGE PK_GENERA_FALTANTES;

-----------------------------------------------------------------------
-- FIN 6-faltas.sql
-----------------------------------------------------------------------
