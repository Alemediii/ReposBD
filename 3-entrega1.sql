---------------------------------------------------------------------------------------
-- EJERCICIO 4. ESTUDIANTES
----------------------------------------------------------------------------------------

-- Originalmente los datos se cargaban desde un CSV mediante una tabla externa.
-- Como ahora los datos ya están insertados vía insercionDB.sql, se comenta ese bloque
-- y se adapta la vista para consultar las tablas existentes.

--/* BLOQUE ORIGINAL: TABLA EXTERNA DESDE CSV
-- GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO PAU;
-- DROP TABLE estudiantes_ext CASCADE CONSTRAINTS;
-- CREATE TABLE estudiantes_ext (...) ORGANIZATION EXTERNAL (...)
--   LOCATION ('datos-estudiantes-pau.csv');
--*/

create or replace view v_estudiantes as
SELECT 
    e.dni, 
    e.nombre, 
    e.apellido as apellidos,
    e.telefono,
    e.correo,
    c.nombre as centro,
    (SELECT LISTAGG(m.nombre, ', ') WITHIN GROUP (ORDER BY m.nombre)
     FROM matriculado mt
     JOIN materia m ON mt.materia_codigo = m.codigo
     WHERE mt.estudiante_dni = e.dni) as detalle_materias
FROM estudiante e
JOIN centro c ON e.centro_codigo = c.codigo
WHERE e.dni IS NOT NULL;

SELECT DISTINCT CENTRO from V_ESTUDIANTES ORDER BY CENTRO;

----------------------------------------------------------------------------------------
-- EJERCICIO 5. MATRÍCULA
----------------------------------------------------------------------------------------

-- Procedimiento para procesar e insertar el listado de materias de un alumno
CREATE OR REPLACE PROCEDURE PR_INSERTA_MATERIAS (
    PESTDNI VARCHAR2, 
    PDETALLE_MATERIAS VARCHAR2
) AS
    v_nom_materia    VARCHAR2(100);
    v_cod_materia    MATERIA.CODIGO%TYPE;
    v_lista          VARCHAR2(2000);
BEGIN
    -- Normalización de la cadena de entrada
    v_lista := PDETALLE_MATERIAS || ',';

    WHILE v_lista IS NOT NULL LOOP
        -- Extracción secuencial de cada materia mediante delimitadores
        v_nom_materia := TRIM(SUBSTR(v_lista, 1, INSTR(v_lista, ',') - 1));
        
        IF v_nom_materia IS NOT NULL THEN
            BEGIN
                -- Obtención del identificador único de la asignatura
                SELECT CODIGO INTO v_cod_materia FROM MATERIA WHERE NOMBRE = v_nom_materia;

                -- Registro en la tabla de matriculación final
                INSERT INTO MATRICULADO (MATERIA_CODIGO, ESTUDIANTE_DNI)
                VALUES (v_cod_materia, PESTDNI);
                
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    DBMS_OUTPUT.PUT_LINE('Error: Materia inexistente -> ' || v_nom_materia);
                WHEN DUP_VAL_ON_INDEX THEN
                    DBMS_OUTPUT.PUT_LINE('Info: Registro duplicado para DNI ' || PESTDNI || ' en ' || v_nom_materia);
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('Fallo en procesamiento de ' || v_nom_materia || ': ' || SQLERRM);
            END;
        END IF;

        -- Actualización del puntero de la lista
        v_lista := SUBSTR(v_lista, INSTR(v_lista, ',') + 1);
    END LOOP;
END;
/

-- Procedimiento principal para la carga masiva de matrículas desde la vista de estudiantes
CREATE OR REPLACE PROCEDURE PR_MATRICULA_ESTUDIANTES AS
BEGIN
    -- Iteración sobre los registros válidos de la vista v_estudiantes
    FOR r IN (SELECT DNI, detalle_materias FROM v_estudiantes WHERE DNI IS NOT NULL AND detalle_materias IS NOT NULL) LOOP
        -- Ejecución de la lógica de inserción por cada alumno
        PR_INSERTA_MATERIAS(r.DNI, r.detalle_materias);
    END LOOP;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Carga de matriculación finalizada correctamente.');
END;
/

----------------------------------------------------------------------------------------
-- EJERCICIO 6. AULAS
----------------------------------------------------------------------------------------

-- Generación automatizada del inventario de aulas por sede.
-- El procedimiento asigna a cada sede el volumen de aulas y capacidad total indicados, 
-- calculando el aforo de examen como el 50% de la CAPACIDAD

create or replace PROCEDURE PR_RELLENA_AULAS 
(
  P_NUM_AULAS IN NUMBER 
, P_CAPACIDAD IN NUMBER 
) AS 
    CURSOR C_SEDES IS SELECT CODIGO FROM SEDE;
    V_CAPACIDAD_EXAMEN NUMBER;
BEGIN
    V_CAPACIDAD_EXAMEN := P_CAPACIDAD/2;
    
    FOR V_SEDE IN C_SEDES LOOP
        FOR contador IN 1..P_NUM_AULAS LOOP
            INSERT INTO aula (codigo,capacidad,capacidad_examen,descripcion,sede_codigo)
            VALUES (CONTADOR,P_CAPACIDAD,V_CAPACIDAD_EXAMEN,NULL,V_SEDE.CODIGO);
        
        END LOOP;
    END LOOP;
    
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('PR_RELLENA_AULAS TERMINADO CORRECTAMENTE');
  
  EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK; 
		-- Marcamos la linea en la que hay fallo, y no hacemos commit
        DBMS_OUTPUT.PUT_LINE('ERROR EN PR_RELLENA_AULAS : ' || SQLERRM);
  
END PR_RELLENA_AULAS;
/



-- Usando la sede como parametro
create or replace PROCEDURE PR_BORRA_AULA_SEDE 
(
  P_CODIGO_SEDE SEDE.CODIGO%TYPE 
) AS 
BEGIN
	-- borramos las aulas una a una
    DELETE FROM AULA WHERE SEDE_CODIGO = P_CODIGO_SEDE;

  COMMIT;
  
  
  EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK; 
		-- Marcamos la linea en la que hay fallo, y no hacemos commit
        DBMS_OUTPUT.PUT_LINE('ERROR EN PR_BORRA_AULA_SEDE : ' || SQLERRM);
  
END PR_BORRA_AULA_SEDE;
/


-- Borramos las aulas con lo anterior
create or replace PROCEDURE PR_BORRA_AULAS AS 
    CURSOR C_SEDES IS SELECT CODIGO FROM SEDE;
BEGIN
  FOR V_SEDE IN C_SEDES LOOP
    PR_BORRA_AULA_SEDE(V_SEDE.CODIGO);
  END LOOP;
  
  COMMIT;
  
  DBMS_OUTPUT.PUT_LINE('PR_BORRA_AULAS TERMINADO CORRECTAMENTE');
  
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK; -- VOLVEMOS A COMO ESTABAMOS ANTES
        DBMS_OUTPUT.PUT_LINE('ERROR EN PR_BORRA_AULAS : ' || SQLERRM);
  
END PR_BORRA_AULAS;




