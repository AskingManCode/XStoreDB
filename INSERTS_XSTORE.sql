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

-- Dehabilitar Triggers para inserts semilla
ALTER TABLE DBO.TIPOS_PERSONAS_TB DISABLE TRIGGER REGISTRAR_TIPO_PERSONA_TR;
ALTER TABLE DBO.PERSONAS_TB DISABLE TRIGGER REGISTRAR_PERSONA_TR;
ALTER TABLE DBO.ROLES_TB DISABLE TRIGGER REGISTRAR_ROL_TR;

-- Inserts Semilla
INSERT INTO DBO.TIPOS_PERSONAS_TB 
(TIPO_PER_Nombre, TIPO_PER_DescuentoPct, TIPO_PER_MontoMeta) 
VALUES 
('SISTEMA', 0.00, 0.00), 
('Vendedor', 10, 0.00),
('Administrador', 15.00, 0.00),  
('Cliente Normal', 0.00, 1000000.00),
('Cliente Frecuente', 5.00, 3000000.00),
('Cliente Premium', 15.00, 5000000.00)

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
    3 -- Administrador
);

INSERT INTO DBO.ROLES_TB (
    ROL_Nombre, ROL_Accesos
)
VALUES 
('Administrador', 'Pantallas_Administrador');

EXEC REGISTRAR_SESION_SP
	@NombreUsuario = 'AskingMansOz',
    @Identificacion = '117980274',
	@PasswordHash = 'xlr8',
	@NombreRol = 'Administrador';

INSERT INTO ESTADOS_ENTREGAS_TB (EST_ENT_Nombre)
VALUES
('En Sucursal'), ('En Camino'), ('Entregado');

-- Activación de Triggers
ALTER TABLE DBO.TIPOS_PERSONAS_TB ENABLE TRIGGER REGISTRAR_TIPO_PERSONA_TR;
ALTER TABLE DBO.PERSONAS_TB ENABLE TRIGGER REGISTRAR_PERSONA_TR;
ALTER TABLE DBO.ROLES_TB ENABLE TRIGGER REGISTRAR_ROL_TR;