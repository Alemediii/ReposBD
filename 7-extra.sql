-----------------------------------------------------------------------
-- 7-extra.sql
-- Procedimientos extra: DESPISTE y MIGRAR_CENTRO
-- Para subir nota
-----------------------------------------------------------------------

SET SERVEROUTPUT ON;

-----------------------------------------------------------------------
-- 1. DESPISTE
-- Reubica a un estudiante en otra aula el mismo día de examen,
-- buscando automáticamente aulas libres para el resto de sus exámenes.
-----------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE DESPISTE(
    P_DNI   IN VARCHAR2,
    P_FECHA IN DATE,
    P_AULA  IN NUMBER,
    P_SEDE  IN NUMBER
) AS
    V_PRIMER_EXAMEN DATE;
BEGIN
    -- Verifica que el alumno tenga un examen en la próxima hora
    SELECT MIN(EXAMEN_FECHAYHORA) INTO V_PRIMER_EXAMEN
    FROM ASISTENCIA
    WHERE ESTUDIANTE_DNI  = P_DNI
      AND EXAMEN_FECHAYHORA BETWEEN SYSDATE AND SYSDATE + 1/24;

    IF V_PRIMER_EXAMEN IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001,
            'No queda menos de una hora para el primer examen del alumno');
    END IF;

    -- Reubica el examen indicado en la nueva aula/sede
    UPDATE ASISTENCIA
    SET EXAMEN_AULA_CODIGO = P_AULA,
        EXAMEN_SEDE_CODIGO = P_SEDE
    WHERE ESTUDIANTE_DNI    = P_DNI
      AND EXAMEN_FECHAYHORA = P_FECHA;

    DBMS_OUTPUT.PUT_LINE('Examen reubicado a aula ' || P_AULA ||
                         ' en sede ' || P_SEDE);

    -- Reubica el resto de exámenes del mismo día en aulas libres
    FOR v_exam IN (
        SELECT EXAMEN_FECHAYHORA, MATERIA_CODIGO
        FROM ASISTENCIA
        WHERE ESTUDIANTE_DNI    = P_DNI
          AND EXAMEN_FECHAYHORA > P_FECHA
          AND TRUNC(EXAMEN_FECHAYHORA) = TRUNC(SYSDATE)
    ) LOOP
        DECLARE
            V_AULA_LIBRE NUMBER;
        BEGIN
            SELECT a.CODIGO
            INTO V_AULA_LIBRE
            FROM AULA a
            WHERE a.SEDE_CODIGO = P_SEDE
              AND NOT EXISTS (
                  SELECT 1 FROM ASISTENCIA ast
                  WHERE ast.EXAMEN_AULA_CODIGO = a.CODIGO
                    AND ast.EXAMEN_SEDE_CODIGO  = a.SEDE_CODIGO
                    AND ast.EXAMEN_FECHAYHORA   = v_exam.EXAMEN_FECHAYHORA
              )
              AND ROWNUM = 1;

            UPDATE ASISTENCIA
            SET EXAMEN_AULA_CODIGO = V_AULA_LIBRE,
                EXAMEN_SEDE_CODIGO = P_SEDE
            WHERE ESTUDIANTE_DNI    = P_DNI
              AND EXAMEN_FECHAYHORA = v_exam.EXAMEN_FECHAYHORA;

            DBMS_OUTPUT.PUT_LINE('Examen ' || TO_CHAR(v_exam.EXAMEN_FECHAYHORA, 'HH24:MI') ||
                                 ' reubicado a aula ' || V_AULA_LIBRE);

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20002,
                    'No hay aula libre en la sede ' || P_SEDE ||
                    ' para el examen del ' ||
                    TO_CHAR(v_exam.EXAMEN_FECHAYHORA, 'DD/MM/YYYY HH24:MI'));
        END;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Estudiante reubicado correctamente');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END DESPISTE;
/

-----------------------------------------------------------------------
-- 2. MIGRAR_CENTRO
-- Traslada todos los exámenes futuros de un centro
-- de una sede origen a una sede destino.
-----------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE MIGRAR_CENTRO(
    P_CENTRO       IN NUMBER,
    P_SEDE_ORIGEN  IN NUMBER,
    P_SEDE_DESTINO IN NUMBER
) AS
    V_AULA_DESTINO NUMBER;
    V_CONTADOR     NUMBER := 0;
BEGIN
    FOR v_exam IN (
        SELECT DISTINCT a.EXAMEN_FECHAYHORA, a.EXAMEN_AULA_CODIGO
        FROM ASISTENCIA a
        JOIN ESTUDIANTE e ON e.DNI = a.ESTUDIANTE_DNI
        WHERE e.CENTRO_CODIGO      = P_CENTRO
          AND a.EXAMEN_SEDE_CODIGO = P_SEDE_ORIGEN
          AND a.EXAMEN_FECHAYHORA  > SYSDATE
    ) LOOP
        FOR v_alumno IN (
            SELECT a.ESTUDIANTE_DNI
            FROM ASISTENCIA a
            JOIN ESTUDIANTE e ON e.DNI = a.ESTUDIANTE_DNI
            WHERE e.CENTRO_CODIGO      = P_CENTRO
              AND a.EXAMEN_SEDE_CODIGO = P_SEDE_ORIGEN
              AND a.EXAMEN_FECHAYHORA  = v_exam.EXAMEN_FECHAYHORA
        ) LOOP
            BEGIN
                -- Busca un aula en la sede destino con capacidad disponible
                SELECT au.CODIGO INTO V_AULA_DESTINO
                FROM AULA au
                WHERE au.SEDE_CODIGO = P_SEDE_DESTINO
                  AND (
                      SELECT COUNT(*) FROM ASISTENCIA a2
                      WHERE a2.EXAMEN_AULA_CODIGO = au.CODIGO
                        AND a2.EXAMEN_SEDE_CODIGO  = P_SEDE_DESTINO
                        AND a2.EXAMEN_FECHAYHORA   = v_exam.EXAMEN_FECHAYHORA
                  ) < au.CAPACIDAD_EXAMEN
                  AND ROWNUM = 1;

                -- Reasigna al alumno
                UPDATE ASISTENCIA
                SET EXAMEN_SEDE_CODIGO = P_SEDE_DESTINO,
                    EXAMEN_AULA_CODIGO = V_AULA_DESTINO
                WHERE ESTUDIANTE_DNI     = v_alumno.ESTUDIANTE_DNI
                  AND EXAMEN_FECHAYHORA  = v_exam.EXAMEN_FECHAYHORA
                  AND EXAMEN_SEDE_CODIGO = P_SEDE_ORIGEN;

                V_CONTADOR := V_CONTADOR + 1;

            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    ROLLBACK;
                    RAISE_APPLICATION_ERROR(-20001,
                        'No hay aulas disponibles en la sede destino ' ||
                        P_SEDE_DESTINO || ' para el examen del ' ||
                        TO_CHAR(v_exam.EXAMEN_FECHAYHORA, 'DD/MM/YYYY HH24:MI'));
            END;
        END LOOP;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Migración completada: ' || V_CONTADOR ||
                         ' asignaciones reubicadas del centro ' || P_CENTRO ||
                         ' a sede ' || P_SEDE_DESTINO);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END MIGRAR_CENTRO;
/

-----------------------------------------------------------------------
-- 3. PRUEBAS (comentadas para no interferir)
-----------------------------------------------------------------------

/* Ejemplo de uso DESPISTE:
BEGIN
    DESPISTE(
        P_DNI   => '88126719U',
        P_FECHA => TO_DATE('09/06/2026 09:00', 'DD/MM/YYYY HH24:MI'),
        P_AULA  => 5,
        P_SEDE  => 3
    );
END;
/
*/

/* Ejemplo de uso MIGRAR_CENTRO:
BEGIN
    MIGRAR_CENTRO(
        P_CENTRO       => 1,      -- C.C. JUAN XXIII
        P_SEDE_ORIGEN  => 1,      -- Facultad de Medicina
        P_SEDE_DESTINO => 3       -- Escuela de Ingenierías Industriales
    );
END;
/
*/

-----------------------------------------------------------------------
-- 3. RESTRICCIONES SEMÁNTICAS (CHECK)
-----------------------------------------------------------------------

ALTER TABLE aula ADD CONSTRAINT aula_capacidad_ck
    CHECK (capacidad > 0 AND capacidad_examen > 0 AND capacidad_examen <= capacidad);

ALTER TABLE asistencia ADD CONSTRAINT asistencia_asiste_ck
    CHECK (asiste IN ('S', 'N'));

ALTER TABLE asistencia ADD CONSTRAINT asistencia_entrega_ck
    CHECK (entrega IN ('S', 'N'));

ALTER TABLE ane ADD CONSTRAINT ane_descabezar_ck
    CHECK (descabezar IN ('S', 'N'));

ALTER TABLE ane ADD CONSTRAINT ane_aulaaparte_ck
    CHECK (aulaaparte IN ('S', 'N'));

-----------------------------------------------------------------------
-- 4. AUDITORÍA: TRIGGER DE MODIFICACIÓN EN ASISTENCIA
-----------------------------------------------------------------------

CREATE TABLE auditoria_asistencia (
    id_auditoria    NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    usuario         VARCHAR2(100),
    fecha_hora      TIMESTAMP,
    operacion       VARCHAR2(10),
    estudiante_dni  VARCHAR2(50),
    fechayhora      DATE,
    aula_codigo     INTEGER,
    sede_codigo     INTEGER,
    materia_codigo  VARCHAR2(100),
    asiste_old      CHAR(1),
    asiste_new      CHAR(1),
    entrega_old     CHAR(1),
    entrega_new     CHAR(1)
);

CREATE OR REPLACE TRIGGER tr_auditoria_asistencia
    AFTER INSERT OR UPDATE OR DELETE ON asistencia
    FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
    ELSE
        v_operacion := 'DELETE';
    END IF;

    INSERT INTO auditoria_asistencia (
        usuario, fecha_hora, operacion,
        estudiante_dni, fechayhora, aula_codigo, sede_codigo, materia_codigo,
        asiste_old, asiste_new, entrega_old, entrega_new
    ) VALUES (
        USER, SYSTIMESTAMP, v_operacion,
        COALESCE(:OLD.estudiante_dni, :NEW.estudiante_dni),
        COALESCE(:OLD.examen_fechayhora, :NEW.examen_fechayhora),
        COALESCE(:OLD.examen_aula_codigo, :NEW.examen_aula_codigo),
        COALESCE(:OLD.examen_sede_codigo, :NEW.examen_sede_codigo),
        COALESCE(:OLD.materia_codigo, :NEW.materia_codigo),
        :OLD.asiste, :NEW.asiste,
        :OLD.entrega, :NEW.entrega
    );
END tr_auditoria_asistencia;
/

-----------------------------------------------------------------------
-- 5. VPD: POLÍTICA DE ACCESO A NIVEL DE FILA
-----------------------------------------------------------------------

-- Función de predicado: los estudiantes ven solo sus asistencias,
-- los vocales ven las de su sede, admin ve todo.
CREATE OR REPLACE FUNCTION f_vpd_asistencia(
    p_schema VARCHAR2,
    p_table  VARCHAR2
) RETURN VARCHAR2 AS
    v_predicate VARCHAR2(2000);
BEGIN
    IF USER = 'ADMIN' THEN
        v_predicate := '1=1';
    ELSIF USER LIKE 'EST\_%' ESCAPE '\' THEN
        v_predicate := 'estudiante_dni = ''' || SUBSTR(USER, 5) || '''';
    ELSIF USER LIKE 'VOC\_%' ESCAPE '\' THEN
        v_predicate := 'examen_sede_codigo IN (
            SELECT codigo FROM sede
            WHERE dni_responsable = ''' || SUBSTR(USER, 5) || '''
               OR dni_secretario  = ''' || SUBSTR(USER, 5) || ''')';
    ELSE
        v_predicate := '1=0';
    END IF;

    RETURN v_predicate;
END f_vpd_asistencia;
/

BEGIN
    DBMS_RLS.DROP_POLICY('ADMIN', 'ASISTENCIA', 'pol_asistencia');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema    => 'ADMIN',
        object_name      => 'ASISTENCIA',
        policy_name      => 'pol_asistencia',
        function_schema  => 'ADMIN',
        policy_function  => 'f_vpd_asistencia',
        statement_types  => 'SELECT, UPDATE, DELETE',
        update_check     => TRUE,
        enable           => TRUE
    );
END;
/

-----------------------------------------------------------------------
-- Verificación
-----------------------------------------------------------------------

SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME IN ('DESPISTE', 'MIGRAR_CENTRO',
                       'TR_AUDITORIA_ASISTENCIA', 'F_VPD_ASISTENCIA')
ORDER BY OBJECT_NAME;

SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, TABLE_NAME, SEARCH_CONDITION
FROM USER_CONSTRAINTS
WHERE CONSTRAINT_NAME LIKE '%\_CK' ESCAPE '\'
ORDER BY TABLE_NAME;

-----------------------------------------------------------------------
-- FIN 7-extra.sql
-----------------------------------------------------------------------
