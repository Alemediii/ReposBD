ALTER INDEX ANE_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX ASISTENCIA_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX AULA_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX CENTRO_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX ESTUDIANTE_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX EXAMEN_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX RELACION_MATERIA_EXAMEN_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX MATERIA_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX RELACION_ESTUDIANTE_MATERIA_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX SEDE_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX RELACION_VOCAL_EXAMEN_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX VOCAL_PK REBUILD TABLESPACE TS_INDICES;
ALTER INDEX SEDE__IDX_RESPONSABLE REBUILD TABLESPACE TS_INDICES;
ALTER INDEX SEDE__IDX_SECRETARIO REBUILD TABLESPACE TS_INDICES;

CREATE INDEX idx_estudiante_apellidos_func ON estudiante (UPPER(apellido)) 
TABLESPACE TS_INDICES;

CREATE BITMAP INDEX idx_estudiante_centro_bmp ON estudiante (centro_codigo) 
TABLESPACE TS_INDICES;

SELECT index_name, index_type, tablespace_name 
FROM user_indexes 
WHERE table_name = 'ESTUDIANTE'; 

-- dejamos el bloque de abajo comentado, ya que al hacer la carga a través de un archivo externo
-- teniendo que ejecutarlo en el bloque de cloud, no se si puede generar problemas
-- TBD: crucialidad del bloque
/*
CREATE MATERIALIZED VIEW VM_ESTUDIANTES
BUILD IMMEDIATE
REFRESH FORCE
START WITH TRUNC(SYSDATE) + 1
NEXT TRUNC(SYSDATE) + 1
AS
SELECT * FROM V_ESTUDIANTES;

-- BLOQUE 4
CREATE PUBLIC SYNONYM S_ESTUDIANTES FOR VM_ESTUDIANTES;
*/

-- Creamos la secuencia para los códigos de centro
CREATE SEQUENCE SEQ_CENTROS 
START WITH 1 
INCREMENT BY 1; 

-- Modificamos el atributo para permitir valores nulos
ALTER TABLE centro MODIFY (sede_codigo NULL); 

CREATE OR REPLACE TRIGGER tr_centros
BEFORE INSERT ON centro FOR EACH ROW
BEGIN
    -- Si el código viene vacío, usamos la secuencia 
    IF :new.codigo IS NULL THEN
        :new.codigo := SEQ_CENTROS.NEXTVAL; 
    END IF;
END tr_centros;
/ 

-- 1. Prueba de inserción manual 
INSERT INTO centro (nombre) VALUES ('Centro de Prueba'); 
SELECT * FROM centro; 
ROLLBACK; -- Borramos la prueba 

-- Los centros y estudiantes ya fueron insertados vía insercionDB.sql.
-- Se mantienen las consultas de verificación.

-- 3. Verificación y consolidación
SELECT * FROM centro; 

SELECT COUNT(*) FROM estudiante;

COMMIT;

/*
COMPROBACIONES PREVIAS: FALLO ENCONTRADO!! Al ejecutar definitivo, se han dropeado las tablas hay que re-rellenarlas
SELECT * FROM sede;
SELECT * FROM aula;
SELECT COUNT(*) as num_centros FROM centro;
*/


CREATE OR REPLACE PACKAGE PK_ASIGNA AS
    -- Función que devuelve las plazas libres en una sede 
    FUNCTION F_PLAZAS (PSEDE IN INTEGER) RETURN NUMBER;
    
    -- Procedimiento para asignar sedes a los centros 
    PROCEDURE PR_ASIGNA_SEDE;
END PK_ASIGNA;
/

CREATE OR REPLACE PACKAGE BODY PK_ASIGNA AS

    FUNCTION F_PLAZAS (PSEDE IN INTEGER) RETURN NUMBER AS
        v_capacidad_examen NUMBER := 0;
        v_estudiantes_total NUMBER := 0;
    BEGIN
        -- 1. Sumamos la capacidad de examen de las aulas de esa sede 
        SELECT NVL(SUM(capacidad_examen), 0) 
        INTO v_capacidad_examen 
        FROM aula 
        WHERE sede_codigo = PSEDE;
        
        -- 2. Restamos los estudiantes de los centros ya asignados a esa sede 
        SELECT COUNT(*) 
        INTO v_estudiantes_total
        FROM estudiante e
        JOIN centro c ON e.centro_codigo = c.codigo
        WHERE c.sede_codigo = PSEDE;
        
        RETURN v_capacidad_examen - v_estudiantes_total; -- Plazas libres 
    END F_PLAZAS;

    PROCEDURE PR_ASIGNA_SEDE AS
        -- Cursor para centros no asignados, ordenados por volumen de alumnos 
        CURSOR c_centros_libres IS
            SELECT c.codigo, c.nombre, COUNT(e.dni) as total_alumnos
            FROM centro c
            LEFT JOIN estudiante e ON c.codigo = e.centro_codigo
            WHERE c.sede_codigo IS NULL
            GROUP BY c.codigo, c.nombre
            ORDER BY total_alumnos DESC;
            
        v_sede_optima INTEGER;
        v_max_plazas  NUMBER;
    BEGIN
        -- PASO 1: Auto-asignación de centros que son sedes de tipo INSTITUTO 
        -- Nota: Usamos UPPER y LIKE por la advertencia sobre nombres duplicados 
        FOR r_auto IN (
            SELECT c.codigo as id_centro, s.codigo as id_sede
            FROM centro c
            JOIN sede s ON UPPER(s.nombre) LIKE '%' || UPPER(c.nombre) || '%'
            WHERE UPPER(s.tipo) = 'INSTITUTO'
        ) LOOP
            UPDATE centro SET sede_codigo = r_auto.id_sede WHERE codigo = r_auto.id_centro;
        END LOOP;

        -- PASO 2: Asignación por plazas libres para el resto de centros 
        FOR r_centro IN c_centros_libres LOOP
            -- Buscamos la sede que más plazas libres tenga en este momento
            SELECT codigo, plazas INTO v_sede_optima, v_max_plazas
            FROM (
                SELECT codigo, F_PLAZAS(codigo) as plazas
                FROM sede
                ORDER BY plazas DESC
            )
            WHERE ROWNUM = 1;
            
            -- Si no caben los alumnos del centro, lanzamos error
            IF v_max_plazas < r_centro.total_alumnos THEN
                RAISE_APPLICATION_ERROR(-20001, 'Capacidad excedida: No hay sede para el centro ' || r_centro.nombre);
            END IF;
            
            -- Asignamos la sede al centro
            UPDATE centro SET sede_codigo = v_sede_optima WHERE codigo = r_centro.codigo;
        END LOOP;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Asignación de sedes completada con éxito.');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END PR_ASIGNA_SEDE;

END PK_ASIGNA;
/


/*
COMPROBACIONES PREVIAS, YA QUE ME SALEN FALLOS POR FALTA DE CAPACIDAD
*/
SELECT c.nombre, COUNT(e.dni) as total_alumnos
FROM centro c
JOIN estudiante e ON c.codigo = e.centro_codigo
WHERE c.nombre = 'I.E.S. CAMILO JOSÉ CELA'
GROUP BY c.nombre;

-- Borramos las aulas insuficientes
EXEC PR_BORRA_AULAS;

-- Creamos un inventario mucho más grande
-- 20 aulas por sede con 100 de capacidad cada una (50 plazas examen)
EXEC PR_RELLENA_AULAS(20, 100);

BEGIN
    PK_ASIGNA.PR_ASIGNA_SEDE;
END;
/


-- comprobaciones finales
SELECT 
    c.nombre AS centro_nombre,
    s.nombre AS sede_asignada,
    s.tipo AS tipo_sede,
    (SELECT COUNT(*) FROM estudiante e WHERE e.centro_codigo = c.codigo) AS num_estudiantes
FROM centro c
LEFT JOIN sede s ON c.sede_codigo = s.codigo
ORDER BY s.nombre, num_estudiantes DESC;

-- ¡NO HAY NULOS, ESO ES BUENO!
SELECT nombre, poblacion 
FROM centro 
WHERE sede_codigo IS NULL;

SELECT 
    s.nombre AS sede,
    (SELECT SUM(capacidad_examen) FROM aula a WHERE a.sede_codigo = s.codigo) AS capacidad_total,
    COUNT(e.dni) AS alumnos_asignados,
    (SELECT SUM(capacidad_examen) FROM aula a WHERE a.sede_codigo = s.codigo) - COUNT(e.dni) AS plazas_libres_reales
FROM sede s
JOIN centro c ON s.codigo = c.sede_codigo
JOIN estudiante e ON c.codigo = e.centro_codigo
GROUP BY s.nombre, s.codigo
ORDER BY plazas_libres_reales DESC;

-- INSTITUTOS AUTOASIGNADOS
SELECT 
    c.nombre AS nombre_centro,
    s.nombre AS nombre_sede
FROM centro c
JOIN sede s ON c.sede_codigo = s.codigo
WHERE UPPER(s.tipo) = 'INSTITUTO' 
  AND UPPER(s.nombre) LIKE '%' || UPPER(c.nombre) || '%';
  
SELECT index_name, tablespace_name, index_type 
FROM user_indexes 
WHERE table_name IN ('ESTUDIANTE', 'CENTRO', 'SEDE');
