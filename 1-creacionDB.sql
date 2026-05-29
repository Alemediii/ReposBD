--select 'drop table '||table_name||' cascade constraints;' from user_tables;
--drop table ANE cascade constraints;
--drop table ASISTENCIA cascade constraints;
--drop table CENTRO cascade constraints;
--drop table ESTUDIANTE cascade constraints;
--drop table EXAMEN cascade constraints;
--drop table EXAMEN_ES_MATERIA cascade constraints;
--drop table MATRICULADO cascade constraints;
--drop table VIGILA cascade constraints;

-------------------------------------------------------------------------------------------------------
-- CREATE
-------------------------------------------------------------------------------------------------------
-- TABLA ANE (Alumno con Necesidades Específicas)
-- DNI (VARCHAR2)   : DNI del estudiante
-- DESCABEZAR       : Si es necesario descabezar el examen del alumno
-- AULAAPARTE       : Si es necesario que el alumno está en un aula aparte
CREATE TABLE ane (
    dni        VARCHAR2(50) NOT NULL,
    descabezar CHAR(1),
    aulaaparte CHAR(1)
);

-- TABLA ASISTENCIA
-- ASISTE             : Si el estudiante ha asistido al examen
-- ENTREGA            : Si el estudiante ha entregado el examen
-- EXAMEN_FECHAYHORA  : Fecha y hora programada del examen
-- EXAMEN_AULA_CODIGO : Código alfanumérico del AULA del examen
-- EXAMEN_SEDE_CODIGO : Código alfanumérico del SEDE del examen
-- MATERIA_CODIGO     : Código de la materia asociada
-- ESTUDIANTE_DNI     : DNI del estudiante que realiza el examen
CREATE TABLE asistencia (
    asiste              CHAR(1),
    entrega             CHAR(1),
    examen_fechayhora   DATE NOT NULL,
    examen_aula_codigo  INTEGER NOT NULL,
    examen_sede_codigo  INTEGER NOT NULL,
    materia_codigo      VARCHAR2(100) NOT NULL,
    estudiante_dni      VARCHAR2(50) NOT NULL
);

-- TABLA AULA
-- CODIGO             : Identificador único del aula
-- CAPACIDAD          : Aforo total del aula
-- CAPACIDAD_EXAMEN   : Aforo permitido durante la realización de exámenes
-- DESCRIPCIÓN        : Detalles adicionales sobre el aula
-- SEDE_CODIGO        : Código de la sede a la que pertenece el aula
CREATE TABLE aula (
    codigo           INTEGER NOT NULL,
    capacidad        INTEGER NOT NULL,
    capacidad_examen INTEGER NOT NULL,
    descripcion      VARCHAR2(500),
    sede_codigo      INTEGER NOT NULL
);

-- TABLA CENTRO
-- CODIGO             : Identificador único del centro educativo
-- NOMBRE             : Denominación oficial del centro
-- DIRECCIÓN          : Ubicación física del centro
-- POBLACIÓN          : Localidad donde se encuentra el centro
-- SEDE_CODIGO        : Código de la sede vinculada al centro
CREATE TABLE centro (
    codigo      INTEGER NOT NULL,
    nombre      VARCHAR2(100) NOT NULL,
    direccion   VARCHAR2(250),
    poblacion   VARCHAR2(250),
    sede_codigo INTEGER NOT NULL
);

-- TABLA ESTUDIANTE
-- DNI                : Documento Nacional de Identidad del estudiante
-- NOMBRE             : Nombre del estudiante
-- APELLIDO           : Apellidos del estudiante
-- TELEFONO           : Número de contacto telefónico
-- CORREO             : Dirección de correo electrónico
-- CENTRO_CODIGO      : Código del centro al que pertenece el alumno
CREATE TABLE estudiante (
    dni           VARCHAR2(50) NOT NULL,
    nombre        VARCHAR2(100) NOT NULL,
    apellido      VARCHAR2(150) NOT NULL,
    telefono      VARCHAR2(100) NOT NULL,
    correo        VARCHAR2(150),
    centro_codigo INTEGER NOT NULL
);

-- TABLA EXAMEN
-- FECHAYHORA         : Momento exacto de inicio del examen
-- VOCAL_DNI          : DNI del vocal responsable del examen
-- AULA_CODIGO        : Código alfanumérico del aula asignada
-- AULA_SEDE_CODIGO   : Código alfanumérico del sede asignada
CREATE TABLE examen (
    fechayhora       DATE NOT NULL,
    vocal_dni        VARCHAR2(50) NOT NULL,
    aula_codigo      INTEGER NOT NULL,
    aula_sede_codigo INTEGER NOT NULL
);

-- TABLA EXAMEN_ES_MATERIA : RELACION ENTRE MATERIA Y EXAMEN
-- MATERIA_CODIGO     : Código de la materia que se evalúa
-- EXAMEN_FECHAYHORA  : Fecha y hora del examen relacionado
-- EXAMEN_AULA_CODIGO : Código del aula del examen relacionado
-- EXAMEN_AULA_CODIGO1: ID numérico del aula del examen relacionado
CREATE TABLE examen_es_materia (
    materia_codigo      VARCHAR2(100) NOT NULL,
    examen_fechayhora   DATE NOT NULL,
    examen_aula_codigo  INTEGER NOT NULL,
    examen_sede_codigo  INTEGER NOT NULL
);

-- TABLA MATERIA
-- CODIGO             : Identificador único de la asignatura
-- NOMBRE             : Nombre completo de la materia
CREATE TABLE materia (
    codigo VARCHAR2(100) NOT NULL,
    nombre VARCHAR2(100) NOT NULL
);

CREATE TABLE matriculado (
    materia_codigo VARCHAR2(100) NOT NULL,
    estudiante_dni VARCHAR2(50) NOT NULL
);

-- TABLA SEDE
-- CODIGO             : Identificador único de la sede de examen
-- NOMBRE             : Nombre de la sede
-- TIPO               : Categoría o clasificación de la sede
-- VOCAL_DNI          : DNI del vocal RESPONSABLE
-- VOCAL_DNI2         : DNI del vocal SECRETARIO
CREATE TABLE sede (
    codigo     		INTEGER NOT NULL,
    nombre     		VARCHAR2(100) NOT NULL,
    tipo       		VARCHAR2(100),
    dni_responsable  	VARCHAR2(50) NOT NULL,
    dni_secretario	VARCHAR2(50) NOT NULL
);

CREATE UNIQUE INDEX sede__idx_responsable ON
    sede (
        dni_responsable
    ASC );

CREATE UNIQUE INDEX sede__idx_secretario ON
    sede (
        dni_secretario
    ASC );

-- TABLA VIGILA :  RELACION ENTRE VOCAL Y EXAMEN
-- VOCAL_DNI          : DNI del vocal que realiza la vigilancia
-- EXAMEN_FECHAYHORA  : Fecha y hora del examen vigilado
-- EXAMEN_AULA_CODIGO : Código del aula donde se vigila
-- EXAMEN_Sede_CODIGO : Código del sede donde se vigila
CREATE TABLE vigila (
    vocal_dni           VARCHAR2(50) NOT NULL,
    examen_fechayhora   DATE NOT NULL,
    examen_aula_codigo  INTEGER NOT NULL,
    examen_sede_codigo  INTEGER NOT NULL
);

-- TABLA VOCAL
-- DNI                : Documento Nacional de Identidad del vocal
-- NOMBRE             : Nombre del vocal
-- APELLIDOS          : Apellidos del vocal
-- TIPO               : Tipo de vocal (ej. corrector, vigilancia)
-- CARGO              : Puesto o cargo específico
-- MATERIA_CODIGO     : Código de la materia asignada al vocal
CREATE TABLE vocal (
    dni            VARCHAR2(50) NOT NULL,
    nombre         VARCHAR2(100) NOT NULL,
    apellidos      VARCHAR2(200) NOT NULL,
    tipo           VARCHAR2(100),
    cargo          VARCHAR2(100),
    materia_codigo VARCHAR2(100)
);

-------------------------------------------------------------------------------------------------------
-- ALTER
-------------------------------------------------------------------------------------------------------

ALTER TABLE ane ADD CONSTRAINT ane_pk PRIMARY KEY ( dni );

ALTER TABLE asistencia
    ADD CONSTRAINT asistencia_pk PRIMARY KEY ( examen_fechayhora,
                                               examen_aula_codigo,
                                               examen_sede_codigo,
                                               materia_codigo,
                                               estudiante_dni );

ALTER TABLE aula ADD CONSTRAINT aula_pk PRIMARY KEY ( codigo,
                                                      sede_codigo );

ALTER TABLE centro ADD CONSTRAINT centro_pk PRIMARY KEY ( codigo );

ALTER TABLE estudiante ADD CONSTRAINT estudiante_pk PRIMARY KEY ( dni );

ALTER TABLE examen
    ADD CONSTRAINT examen_pk PRIMARY KEY ( fechayhora,
                                           aula_codigo,
                                           aula_sede_codigo );

ALTER TABLE examen_es_materia
    ADD CONSTRAINT relacion_materia_examen_pk PRIMARY KEY ( materia_codigo,
                                                            examen_fechayhora,
                                                            examen_aula_codigo,
                                                            examen_sede_codigo );

ALTER TABLE materia ADD CONSTRAINT materia_pk PRIMARY KEY ( codigo );

ALTER TABLE matriculado ADD CONSTRAINT relacion_estudiante_materia_pk PRIMARY KEY ( materia_codigo,
                                                                                    estudiante_dni );

ALTER TABLE sede ADD CONSTRAINT sede_pk PRIMARY KEY ( codigo );

ALTER TABLE vigila
    ADD CONSTRAINT relacion_vocal_examen_pk PRIMARY KEY ( vocal_dni,
                                                          examen_fechayhora,
                                                          examen_aula_codigo,
                                                          examen_sede_codigo  );

ALTER TABLE vocal ADD CONSTRAINT vocal_pk PRIMARY KEY ( dni );

ALTER TABLE ane
    ADD CONSTRAINT ane_estudiante_fk FOREIGN KEY ( dni )
        REFERENCES estudiante ( dni );

ALTER TABLE asistencia
    ADD CONSTRAINT asistencia_estudiante_fk FOREIGN KEY ( estudiante_dni )
        REFERENCES estudiante ( dni );

ALTER TABLE asistencia
    ADD CONSTRAINT asistencia_examen_fk FOREIGN KEY ( examen_fechayhora,
                                                      examen_aula_codigo,
                                                      examen_sede_codigo  )
        REFERENCES examen ( fechayhora,
                            aula_codigo,
                            aula_sede_codigo );

ALTER TABLE asistencia
    ADD CONSTRAINT asistencia_materia_fk FOREIGN KEY ( materia_codigo )
        REFERENCES materia ( codigo );

ALTER TABLE aula
    ADD CONSTRAINT aula_sede_fk FOREIGN KEY ( sede_codigo )
        REFERENCES sede ( codigo );

ALTER TABLE centro
    ADD CONSTRAINT centro_sede_fk FOREIGN KEY ( sede_codigo )
        REFERENCES sede ( codigo );

ALTER TABLE estudiante
    ADD CONSTRAINT estudiante_centro_fk FOREIGN KEY ( centro_codigo )
        REFERENCES centro ( codigo );

ALTER TABLE examen
    ADD CONSTRAINT examen_aula_fk FOREIGN KEY ( aula_codigo,
                                                aula_sede_codigo )
        REFERENCES aula ( codigo,
                          sede_codigo );

ALTER TABLE examen
    ADD CONSTRAINT examen_vocal_fk FOREIGN KEY ( vocal_dni )
        REFERENCES vocal ( dni );

ALTER TABLE matriculado
    ADD CONSTRAINT r_estu_materia_estu_fk FOREIGN KEY ( estudiante_dni )
        REFERENCES estudiante ( dni );

ALTER TABLE matriculado
    ADD CONSTRAINT r_estu_materia_materia_fk FOREIGN KEY ( materia_codigo )
        REFERENCES materia ( codigo );

ALTER TABLE examen_es_materia
    ADD CONSTRAINT r_materia_examen_examen_fk FOREIGN KEY ( examen_fechayhora,
                                                            examen_aula_codigo,
                                                            examen_sede_codigo  )
        REFERENCES examen ( fechayhora,
                            aula_codigo,
                            aula_sede_codigo );

ALTER TABLE examen_es_materia
    ADD CONSTRAINT r_materia_examen_materia_fk FOREIGN KEY ( materia_codigo )
        REFERENCES materia ( codigo );

ALTER TABLE vigila
    ADD CONSTRAINT r_vocal_examen_examen_fk FOREIGN KEY ( examen_fechayhora,
                                                          examen_aula_codigo,
                                                          examen_sede_codigo  )
        REFERENCES examen ( fechayhora,
                            aula_codigo,
                            aula_sede_codigo );

ALTER TABLE vigila
    ADD CONSTRAINT r_vocal_examen_vocal_fk FOREIGN KEY ( vocal_dni )
        REFERENCES vocal ( dni );

ALTER TABLE sede
    ADD CONSTRAINT sede_vocal_fk FOREIGN KEY ( dni_responsable )
        REFERENCES vocal ( dni );

ALTER TABLE sede
    ADD CONSTRAINT sede_vocal_fkv1 FOREIGN KEY ( dni_secretario )
        REFERENCES vocal ( dni );

ALTER TABLE vocal
    ADD CONSTRAINT vocal_materia_fk FOREIGN KEY ( materia_codigo )
        REFERENCES materia ( codigo );

