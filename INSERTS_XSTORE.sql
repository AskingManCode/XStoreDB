------------------------------
--- ****** DATABASE ****** ---
IF DB_ID('XSTORE') IS NULL
BEGIN
    CREATE DATABASE XSTORE;
END
GO

USE XSTORE;
GO

--- INSERTS DE PRUEBA ---
INSERT INTO DBO.TIPOS_PERSONAS_TB(
    TIPO_PER_Nombre,
    TIPO_PER_DescuentoPct,
    TIPO_PER_MontoMeta 
)
VALUES (
    'Administrador',
    20,
    0
);

INSERT INTO DBO.PERSONAS_TB(
	PER_Identificacion,
	PER_NombreCompleto,
	PER_Telefono,
	PER_Correo,
	PER_Direccion,
    PER_TIPO_PER_ID
)
VALUES (
    '123456789',
    'Sebastián',
    '12345678',
    'a@gmail.com',
    'Tejar',
    1
);

INSERT INTO DBO.ROLES_TB (
    ROL_Nombre
)
VALUES (
    'Cliente'
);

SELECT * FROM ROLES_TB

INSERT INTO DBO.SESIONES_TB (
    SESION_PER_ID,
    SESION_NombreUsuario,
    SESION_PwdHash,
    SESION_ROL_ID
)
VALUES (
    1,
    'AskingMansOn',
    '123456789',
    3
);

INSERT INTO DBO.SESIONES_TB (
    SESION_PER_ID,
    SESION_NombreUsuario,
    SESION_PwdHash,
    SESION_ROL_ID
)
VALUES (
    1,
    'RAMÓN123',
    '123456789',
    1
);