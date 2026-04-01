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
-- Primer insert del sistema
INSERT INTO DBO.TIPOS_PERSONAS_TB (
    TIPO_PER_Nombre, 
    TIPO_PER_DescuentoPct, 
    TIPO_PER_MontoMeta
) 
VALUES ('SISTEMA', 0.00, 0.00), ('Administrador', 20, 0);

INSERT INTO DBO.PERSONAS_TB (
    PER_Identificacion,
    PER_NombreCompleto,
    PER_Telefono,
    PER_Correo,
    PER_Direccion,
    PER_TIPO_PER_ID
)
VALUES (
    '000000000',
    'SISTEMA', 
    '00000000', 
    'system@xstore.com', 
    'N/A', 
    1
), (
    '117980274',
    'Sebastián Jiménez Arrieta',
    '87876607',
    'sebasjimearrieta@gmail.com',
    'Tejar, El Guarco',
    2 -- Administrador
);

INSERT INTO DBO.ROLES_TB (
    ROL_Nombre, ROL_Accesos
)
VALUES (
    'Administrador', 'Pantalla_Menú, Pantalla_Editar_Productos, Pantalla_CRUD_Usuarios'
);

EXEC REGISTRAR_SESION_SP
	@Persona_ID = 2,
	@NombreUsuario = 'AskingMansOz',
	@PasswordHash = '1234',
	@NombreRol = 'Administrador';