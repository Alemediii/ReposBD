-----------------------------------------------------------------------
-- 6-faltas.sql
-- Datos de prueba + funcionalidades pendientes
-----------------------------------------------------------------------

SET DEFINE OFF;
SET SERVEROUTPUT ON;

-----------------------------------------------------------------------
-- 1. AULAS
-----------------------------------------------------------------------

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
        v_vocal_dni vocal.dni%TYPE;
        v_total_materias INTEGER;
    BEGIN
        SELECT codigo BULK COLLECT INTO v_materias FROM materia ORDER BY codigo;
        v_total_materias := v_materias.COUNT;

        FOR i IN 1..v_total_materias LOOP
            v_fecha_actual := v_fecha_inicio + FLOOR((i-1) / 4);
            v_fecha_actual := v_fecha_actual + MOD(((i-1) * 2), 8) / 24;

            FOR r_sede IN (SELECT codigo FROM sede ORDER BY codigo) LOOP
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

                    SELECT dni INTO v_vocal_dni
                    FROM vocal
                    WHERE NOT EXISTS (
                        SELECT 1 FROM vigila v
                        WHERE v.vocal_dni = vocal.dni
                          AND v.examen_fechayhora = v_fecha_actual
                    )
                    AND ROWNUM = 1;

                    INSERT INTO examen (fechayhora, vocal_dni, aula_codigo, aula_sede_codigo)
                    VALUES (v_fecha_actual, v_vocal_dni, v_aula_disponible, r_sede.codigo);

                    INSERT INTO examen_es_materia (materia_codigo, examen_fechayhora, examen_aula_codigo, examen_sede_codigo)
                    VALUES (v_materias(i), v_fecha_actual, v_aula_disponible, r_sede.codigo);

                    INSERT INTO vigila (vocal_dni, examen_fechayhora, examen_aula_codigo, examen_sede_codigo)
                    VALUES (v_vocal_dni, v_fecha_actual, v_aula_disponible, r_sede.codigo);

                    INSERT INTO asistencia (asiste, entrega, examen_fechayhora, examen_aula_codigo, examen_sede_codigo, materia_codigo, estudiante_dni)
                    SELECT 'S', 'S', v_fecha_actual, v_aula_disponible, r_sede.codigo, v_materias(i), mt.estudiante_dni
                    FROM matriculado mt
                    JOIN estudiante e ON e.dni = mt.estudiante_dni
                    JOIN centro c ON c.codigo = e.centro_codigo
                    WHERE mt.materia_codigo = v_materias(i)
                      AND c.sede_codigo = r_sede.codigo;

                EXCEPTION
                    WHEN NO_DATA_FOUND THEN NULL;
                END;
            END LOOP;
        END LOOP;

        INSERT INTO ane (dni, descabezar, aulaaparte)
        SELECT dni, 'S', 'N' FROM (SELECT dni FROM estudiante SAMPLE(1)) WHERE ROWNUM <= 10;
        INSERT INTO ane (dni, descabezar, aulaaparte)
        SELECT dni, 'N', 'S' FROM (SELECT dni FROM estudiante SAMPLE(1) WHERE dni NOT IN (SELECT dni FROM ane)) WHERE ROWNUM <= 5;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Datos generados correctamente.');
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK; RAISE;
    END PR_GENERAR;

END PK_GENERA_FALTANTES;
/

BEGIN PK_GENERA_FALTANTES.PR_GENERAR; END;
/

-----------------------------------------------------------------------
-- 3. VISTA: ESTUDIANTE CONSULTA SU AULA
-----------------------------------------------------------------------

CREATE OR REPLACE VIEW V_MIS_EXAMENES AS
SELECT 
    e.dni AS ESTUDIANTE_DNI,
    e.nombre || ' ' || e.apellido AS ESTUDIANTE,
    m.nombre AS MATERIA,
    a.examen_fechayhora AS FECHA,
    au.codigo AS AULA,
    s.nombre AS SEDE,
    a.asiste,
    a.entrega
FROM asistencia a
JOIN estudiante e ON e.dni = a.estudiante_dni
JOIN materia m ON m.codigo = a.materia_codigo
JOIN aula au ON au.codigo = a.examen_aula_codigo AND au.sede_codigo = a.examen_sede_codigo
JOIN sede s ON s.codigo = a.examen_sede_codigo;

-----------------------------------------------------------------------
-- 4. PAQUETE: RESPONSABLE DE SEDE
-----------------------------------------------------------------------

CREATE OR REPLACE PACKAGE PK_GESTION_SEDE AS
    FUNCTION F_VER_AULAS(P_SEDE INTEGER) RETURN SYS_REFCURSOR;
    FUNCTION F_VER_ASIGNACIONES(P_SEDE INTEGER, P_FECHA DATE) RETURN SYS_REFCURSOR;
    PROCEDURE PR_INSERTAR_AULA(P_SEDE INTEGER, P_CAPACIDAD INTEGER);
    PROCEDURE PR_ASIGNAR_VIGILANTE(P_SEDE INTEGER, P_FECHA DATE, P_AULA INTEGER, P_VOCAL VARCHAR2);
END PK_GESTION_SEDE;
/

CREATE OR REPLACE PACKAGE BODY PK_GESTION_SEDE AS

    FUNCTION F_VER_AULAS(P_SEDE INTEGER) RETURN SYS_REFCURSOR AS
        c SYS_REFCURSOR;
    BEGIN
        OPEN c FOR SELECT codigo, capacidad, capacidad_examen, descripcion
                   FROM aula WHERE sede_codigo = P_SEDE;
        RETURN c;
    END;

    FUNCTION F_VER_ASIGNACIONES(P_SEDE INTEGER, P_FECHA DATE) RETURN SYS_REFCURSOR AS
        c SYS_REFCURSOR;
    BEGIN
        OPEN c FOR
            SELECT a.examen_aula_codigo AS AULA, a.examen_fechayhora AS FECHA,
                   m.nombre AS MATERIA, COUNT(a.estudiante_dni) AS ALUMNOS
            FROM asistencia a
            JOIN materia m ON m.codigo = a.materia_codigo
            WHERE a.examen_sede_codigo = P_SEDE
              AND TRUNC(a.examen_fechayhora) = TRUNC(P_FECHA)
            GROUP BY a.examen_aula_codigo, a.examen_fechayhora, m.nombre;
        RETURN c;
    END;

    PROCEDURE PR_INSERTAR_AULA(P_SEDE INTEGER, P_CAPACIDAD INTEGER) AS
        v_max INTEGER;
    BEGIN
        SELECT NVL(MAX(codigo), 0) + 1 INTO v_max FROM aula WHERE sede_codigo = P_SEDE;
        INSERT INTO aula (codigo, capacidad, capacidad_examen, descripcion, sede_codigo)
        VALUES (v_max, P_CAPACIDAD, P_CAPACIDAD/2, NULL, P_SEDE);
        COMMIT;
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END;

    PROCEDURE PR_ASIGNAR_VIGILANTE(P_SEDE INTEGER, P_FECHA DATE, P_AULA INTEGER, P_VOCAL VARCHAR2) AS
    BEGIN
        INSERT INTO vigila (vocal_dni, examen_fechayhora, examen_aula_codigo, examen_sede_codigo)
        VALUES (P_VOCAL, P_FECHA, P_AULA, P_SEDE);
        COMMIT;
    EXCEPTION WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('El vocal ya está asignado a ese examen.');
    WHEN OTHERS THEN ROLLBACK; RAISE;
    END;

END PK_GESTION_SEDE;
/

-----------------------------------------------------------------------
-- 5. PAQUETE: RESPONSABLE DE AULA (registra alumnos presentes)
-----------------------------------------------------------------------

CREATE OR REPLACE PACKAGE PK_GESTION_AULA AS
    PROCEDURE PR_REGISTRAR_ASISTENCIA(P_DNI VARCHAR2, P_FECHA DATE, P_AULA INTEGER, P_SEDE INTEGER, P_MATERIA VARCHAR2, P_ASISTE CHAR, P_ENTREGA CHAR);
    FUNCTION F_ALUMNOS_EN_AULA(P_FECHA DATE, P_AULA INTEGER, P_SEDE INTEGER) RETURN NUMBER;
END PK_GESTION_AULA;
/

CREATE OR REPLACE PACKAGE BODY PK_GESTION_AULA AS

    PROCEDURE PR_REGISTRAR_ASISTENCIA(P_DNI VARCHAR2, P_FECHA DATE, P_AULA INTEGER, P_SEDE INTEGER, P_MATERIA VARCHAR2, P_ASISTE CHAR, P_ENTREGA CHAR) AS
    BEGIN
        UPDATE asistencia
        SET asiste = P_ASISTE, entrega = P_ENTREGA
        WHERE estudiante_dni = P_DNI
          AND examen_fechayhora = P_FECHA
          AND examen_aula_codigo = P_AULA
          AND examen_sede_codigo = P_SEDE
          AND materia_codigo = P_MATERIA;
        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO asistencia (asiste, entrega, examen_fechayhora, examen_aula_codigo, examen_sede_codigo, materia_codigo, estudiante_dni)
            VALUES (P_ASISTE, P_ENTREGA, P_FECHA, P_AULA, P_SEDE, P_MATERIA, P_DNI);
        END IF;
        COMMIT;
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END;

    FUNCTION F_ALUMNOS_EN_AULA(P_FECHA DATE, P_AULA INTEGER, P_SEDE INTEGER) RETURN NUMBER AS
        v_total NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_total
        FROM asistencia
        WHERE examen_fechayhora = P_FECHA
          AND examen_aula_codigo = P_AULA
          AND examen_sede_codigo = P_SEDE;
        RETURN v_total;
    END;

END PK_GESTION_AULA;
/

-----------------------------------------------------------------------
-- 6. VISTA: VIGILANTE CONSULTA SU ASIGNACIÓN
-----------------------------------------------------------------------

CREATE OR REPLACE VIEW V_MIS_VIGILANCIAS AS
SELECT 
    v.vocal_dni AS VOCAL_DNI,
    voc.nombre || ' ' || voc.apellidos AS VOCAL,
    v.examen_fechayhora AS FECHA,
    v.examen_aula_codigo AS AULA,
    s.nombre AS SEDE,
    (SELECT COUNT(*) FROM asistencia a 
     WHERE a.examen_fechayhora = v.examen_fechayhora
       AND a.examen_aula_codigo = v.examen_aula_codigo
       AND a.examen_sede_codigo = v.examen_sede_codigo) AS ALUMNOS
FROM vigila v
JOIN vocal voc ON voc.dni = v.vocal_dni
JOIN sede s ON s.codigo = v.examen_sede_codigo;

-----------------------------------------------------------------------
-- 7. PAQUETE: PERSONAL SAVED (gestión central)
-----------------------------------------------------------------------

CREATE OR REPLACE PACKAGE PK_GESTION_SAVED AS
    FUNCTION F_OCUPACION_GLOBAL(P_FECHA DATE) RETURN SYS_REFCURSOR;
    FUNCTION F_ESTUDIANTES_POR_AULA(P_SEDE INTEGER, P_FECHA DATE) RETURN SYS_REFCURSOR;
    PROCEDURE PR_ASIGNAR_RESPONSABLE_SEDE(P_SEDE INTEGER, P_RESPONSABLE VARCHAR2, P_SECRETARIO VARCHAR2);
END PK_GESTION_SAVED;
/

CREATE OR REPLACE PACKAGE BODY PK_GESTION_SAVED AS

    FUNCTION F_OCUPACION_GLOBAL(P_FECHA DATE) RETURN SYS_REFCURSOR AS
        c SYS_REFCURSOR;
    BEGIN
        OPEN c FOR
            SELECT s.nombre AS SEDE, a.examen_aula_codigo AS AULA,
                   COUNT(a.estudiante_dni) AS ALUMNOS_ASIGNADOS,
                   SUM(CASE WHEN a.asiste = 'S' THEN 1 ELSE 0 END) AS ALUMNOS_PRESENTES,
                   au.capacidad_examen AS AFORO_MAXIMO
            FROM asistencia a
            JOIN sede s ON s.codigo = a.examen_sede_codigo
            JOIN aula au ON au.codigo = a.examen_aula_codigo AND au.sede_codigo = a.examen_sede_codigo
            WHERE TRUNC(a.examen_fechayhora) = TRUNC(P_FECHA)
            GROUP BY s.nombre, a.examen_aula_codigo, au.capacidad_examen
            ORDER BY s.nombre, a.examen_aula_codigo;
        RETURN c;
    END;

    FUNCTION F_ESTUDIANTES_POR_AULA(P_SEDE INTEGER, P_FECHA DATE) RETURN SYS_REFCURSOR AS
        c SYS_REFCURSOR;
    BEGIN
        OPEN c FOR
            SELECT au.codigo AS AULA, m.nombre AS MATERIA,
                   COUNT(a.estudiante_dni) AS TOTAL_ALUMNOS,
                   SUM(CASE WHEN a.asiste = 'S' THEN 1 ELSE 0 END) AS PRESENTES
            FROM aula au
            JOIN examen e ON e.aula_codigo = au.codigo AND e.aula_sede_codigo = au.sede_codigo
            JOIN examen_es_materia em ON em.examen_fechayhora = e.fechayhora
                                      AND em.examen_aula_codigo = e.aula_codigo
                                      AND em.examen_sede_codigo = e.aula_sede_codigo
            JOIN materia m ON m.codigo = em.materia_codigo
            LEFT JOIN asistencia a ON a.examen_fechayhora = e.fechayhora
                                   AND a.examen_aula_codigo = e.aula_codigo
                                   AND a.examen_sede_codigo = e.aula_sede_codigo
            WHERE au.sede_codigo = P_SEDE
              AND TRUNC(e.fechayhora) = TRUNC(P_FECHA)
            GROUP BY au.codigo, m.nombre
            ORDER BY au.codigo;
        RETURN c;
    END;

    PROCEDURE PR_ASIGNAR_RESPONSABLE_SEDE(P_SEDE INTEGER, P_RESPONSABLE VARCHAR2, P_SECRETARIO VARCHAR2) AS
    BEGIN
        UPDATE sede SET dni_responsable = P_RESPONSABLE, dni_secretario = P_SECRETARIO
        WHERE codigo = P_SEDE;
        COMMIT;
    EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;
    END;

END PK_GESTION_SAVED;
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
