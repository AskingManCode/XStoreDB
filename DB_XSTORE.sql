------------------------------
--- ****** DATABASE ****** ---
IF DB_ID('XSTORE') IS NULL
BEGIN
    CREATE DATABASE XSTORE;
END 
GO 

USE XSTORE;
GO

---- ****** TABLAS ****** ----
IF OBJECT_ID('DBO.TIPOS_PERSONAS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.TIPOS_PERSONAS_TB(
        TIPO_PER_ID INT IDENTITY(1,1), -- PK
        TIPO_PER_Nombre VARCHAR(50) NOT NULL, -- Cliente Normal, Cliente Frecuente, Cliente Premium -- extra: Vendedor, Administrador
        TIPO_PER_DescuentoPct DECIMAL(5,2) NOT NULL, -- 0%, 10%, 25% -- extra: 15%, 20%
        TIPO_PER_MontoMeta DECIMAL(10,2) NOT NULL, 
        TIPO_PER_Estado BIT NOT NULL
            CONSTRAINT DF_TIPO_PER_Estado 
                DEFAULT (1),

        -- PRIMARY KEY

        CONSTRAINT PK_TIPOS_PERSONAS_TB
            PRIMARY KEY(TIPO_PER_ID),

        -- CHECKS

        CONSTRAINT CK_TIPO_PER_Nombre
            CHECK (LEN(TRIM(TIPO_PER_Nombre)) > 0
                    AND TIPO_PER_Nombre NOT LIKE ' %'
                    AND TIPO_PER_Nombre NOT LIKE '% '
                    AND TIPO_PER_Nombre NOT LIKE '%  %'),

        CONSTRAINT CK_TIPO_PER_DescuentoPct
            CHECK (TIPO_PER_DescuentoPct BETWEEN 0.00 AND 100.00),

        CONSTRAINT CK_TIPO_PER_MontoMeta
            CHECK (TIPO_PER_MontoMeta >= 0.00),

        -- UNIQUES

        CONSTRAINT UQ_TIPO_PER_Nombre
            UNIQUE(TIPO_PER_Nombre)
    );
END
GO


IF OBJECT_ID('DBO.PERSONAS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.PERSONAS_TB( -- Personas o Empresa: Cliente, Proveedor, Administrador, Vendedor
	    PER_ID INT IDENTITY(1,1), -- PK
	    PER_Identificacion VARCHAR(50) NOT NULL, -- Cédula Identidad, Cédula Juridica
	    PER_NombreCompleto VARCHAR(150) NOT NULL,
	    PER_Telefono VARCHAR(25) NULL,
	    PER_Correo VARCHAR(150) NULL,
	    PER_Direccion VARCHAR(175) NULL,
	    PER_FechaRegistro DATETIME2 NOT NULL
            CONSTRAINT DF_PER_FechaRegistro 
                DEFAULT (SYSDATETIME()),
        PER_TIPO_PER_ID INT NOT NULL, -- FK
	    PER_Estado BIT NOT NULL 
		    CONSTRAINT DF_PER_Estado 
                DEFAULT(1),

        -- PRIMARY KEY

        CONSTRAINT PK_PERSONAS_TB
            PRIMARY KEY(PER_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_PERSONAS_TIPO_PER_ID
            FOREIGN KEY (PER_TIPO_PER_ID)
                REFERENCES DBO.TIPOS_PERSONAS_TB(TIPO_PER_ID),

        -- CHECKS

        CONSTRAINT CK_PER_Identificacion
            CHECK (LEN(TRIM(PER_Identificacion)) >= 9
                    AND PER_Identificacion NOT LIKE ' %'
                    AND PER_Identificacion NOT LIKE '% '
                    AND PER_Identificacion NOT LIKE '% %'
                    AND PER_Identificacion NOT LIKE '%[^A-Za-z0-9]%'),
        
        CONSTRAINT CK_PER_NombreCompleto
            CHECK (LEN(TRIM(PER_NombreCompleto)) > 0 
                    AND PER_NombreCompleto NOT LIKE ' %'
                    AND PER_NombreCompleto NOT LIKE '% '
                    AND PER_NombreCompleto NOT LIKE '%  %'),

        CONSTRAINT CK_PERSONAS_CONTACTO -- Agregación de Correo, Teléfono o ambos, pero nunca ninguno
            CHECK ((PER_Telefono IS NOT NULL AND LEN(TRIM(PER_Telefono)) >= 8)
                    OR 
                    (PER_Correo IS NOT NULL AND LEN(TRIM(PER_Correo)) >= 7)),

        CONSTRAINT CK_PER_Telefono
            CHECK (PER_Telefono IS NULL 
                    OR (LEN(TRIM(PER_Telefono)) >= 8
                        AND PER_Telefono NOT LIKE ' %'
                        AND PER_Telefono NOT LIKE '% '
                        AND PER_Telefono NOT LIKE '% %'
                        AND PER_Telefono NOT LIKE '%[^0-9]%')),

        CONSTRAINT CK_PER_Correo
            CHECK (PER_Correo IS NULL 
                    OR (LEN(TRIM(PER_Correo)) >= 7
                        AND PER_Correo NOT LIKE ' %'
                        AND PER_Correo NOT LIKE '% ' 
                        AND PER_Correo NOT LIKE '% %'
                        AND PER_Correo LIKE '%_@_%._%'
                        AND PER_Correo NOT LIKE '%@%@%'
                        AND PER_Correo NOT LIKE '%..%'
                        AND PER_Correo NOT LIKE '%@.%'
                        AND PER_Correo NOT LIKE '[.@]%'
                        AND PER_Correo NOT LIKE '%[@.]')),

        CONSTRAINT CK_PER_Direccion
            CHECK (PER_Direccion IS NULL 
                    OR (LEN(TRIM(PER_Direccion)) > 0
                    AND PER_Direccion NOT LIKE ' %'
                    AND PER_Direccion NOT LIKE '% '
                    AND PER_Direccion NOT LIKE '%  %')),

        -- UNIQUES

        CONSTRAINT UQ_PER_Identificacion
            UNIQUE(PER_Identificacion)
    ); 
END
GO



IF OBJECT_ID('DBO.AUDITORIAS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.AUDITORIAS_TB( 
	    AUD_ID BIGINT IDENTITY(1,1), -- PK
        AUD_PER_ID INT NOT NULL, -- FK          -- ID de la Persona
	    AUD_Accion VARCHAR(25) NOT NULL,        -- Acción en base de datos
	    AUD_TablaAfectada VARCHAR(75) NOT NULL, -- Nombre tabla afectada
	    AUD_FilaAfectada BIGINT NOT NULL,       -- ID de la fila afectada
	    AUD_Descripcion VARCHAR(250) NOT NULL,  -- Descripción auditable
        AUD_Antes VARCHAR(1000) NULL
            CONSTRAINT DF_AUD_Antes
                DEFAULT (NULL), 
        AUD_Despues VARCHAR(1000) NULL
            CONSTRAINT DF_AUD_Despues
                DEFAULT (NULL),
	    AUD_FechaHora DATETIME2 NOT NULL
            CONSTRAINT DF_AUD_FechaHora
                DEFAULT(SYSDATETIME()),
        
        -- PRIMARY KEY

        CONSTRAINT PK_AUDITORIAS_TB
            PRIMARY KEY(AUD_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_AUDITORIAS_PER_ID
            FOREIGN KEY (AUD_PER_ID)
                REFERENCES PERSONAS_TB(PER_ID),

        -- CHECKS

        CONSTRAINT CK_AUD_DB_Accion
            CHECK (AUD_Accion IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')),

        CONSTRAINT CK_AUD_TablaAfectada
            CHECK (LEN(TRIM(AUD_TablaAfectada)) > 0
                    AND AUD_TablaAfectada NOT LIKE ' %'
                    AND AUD_TablaAfectada NOT LIKE '% ' 
                    AND AUD_TablaAfectada NOT LIKE '%  %'),

        CONSTRAINT CK_AUD_FilaAfectada
            CHECK (AUD_FilaAfectada >= 0),

        CONSTRAINT CK_AUD_Descripcion
            CHECK (LEN(TRIM(AUD_Descripcion)) > 10 -- Mínimo de detalle para que sea un comentario útil
                    AND AUD_Descripcion NOT LIKE ' %'
                    AND AUD_Descripcion NOT LIKE '% '
                    AND AUD_Descripcion NOT LIKE '%  %')
    ); 
END
GO


IF OBJECT_ID('DBO.ROLES_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.ROLES_TB(
	    ROL_ID INT IDENTITY(1,1), -- PK
        ROL_Nombre VARCHAR(50) NOT NULL, -- Sistema, Administrador, Vendedor, Cliente, 
        ROL_Accesos VARCHAR(500) NOT NULL, -- Pantallas a las que accede el rol
        ROL_Estado BIT NOT NULL 
            CONSTRAINT DF_ROL_Estado
                DEFAULT (1),

        -- PRIMARY KEY

        CONSTRAINT PK_ROLES_TB
            PRIMARY KEY (ROL_ID),

        -- CHECKS

        CONSTRAINT CK_ROL_Nombre
            CHECK ((LEN(TRIM(ROL_Nombre)) > 0)
                    AND ROL_Nombre NOT LIKE ' %'
                    AND ROL_Nombre NOT LIKE '% '
                    AND ROL_Nombre NOT LIKE '%  %'),

        CONSTRAINT CK_ROL_Accesos
            CHECK ((LEN(TRIM(ROL_Accesos)) > 0)
                    AND ROL_Accesos NOT LIKE ' %'
                    AND ROL_Accesos NOT LIKE '% '
                    AND ROL_Accesos NOT LIKE '%  %'),

        -- UNIQUES

        CONSTRAINT UQ_ROL_Nombre
            UNIQUE(ROL_Nombre)
    ); 
END
GO


IF OBJECT_ID('DBO.SESIONES_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.SESIONES_TB(
	    SESION_ID INT IDENTITY(1,1), -- PK
        SESION_PER_ID INT NOT NULL, -- FK
	    SESION_NombreUsuario VARCHAR(75) NOT NULL,
	    SESION_PwdHash VARCHAR(255) NOT NULL,
	    SESION_ROL_ID INT NOT NULL, -- FK
        SESION_Estado BIT NOT NULL
            CONSTRAINT DF_SESION_Estado
                DEFAULT (1),

        -- PRIMARY KEY

        CONSTRAINT PK_SESIONES_TB
            PRIMARY KEY(SESION_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_SESIONES_PER_ID
            FOREIGN KEY(SESION_PER_ID)
                REFERENCES PERSONAS_TB(PER_ID),

        CONSTRAINT FK_SESIONES_ROL_ID
            FOREIGN KEY(SESION_ROL_ID)
                REFERENCES ROLES_TB(ROL_ID),

        -- CHECKS

        CONSTRAINT CK_SESION_NombreUsuario
            CHECK (LEN(TRIM(SESION_NombreUsuario)) > 0
                    AND SESION_NombreUsuario NOT LIKE ' %'
                    AND SESION_NombreUsuario NOT LIKE '% '
                    AND SESION_NombreUsuario NOT LIKE '% %'),

        CONSTRAINT CK_SESION_PwdHash
            CHECK(LEN(TRIM(SESION_PwdHash)) > 0
                AND SESION_PwdHash NOT LIKE ' %'
                AND SESION_PwdHash NOT LIKE '% '
                AND SESION_PwdHash NOT LIKE '% %'),

        -- UNIQUES

        CONSTRAINT UQ_SESION_NombreUsuario
            UNIQUE (SESION_NombreUsuario),

        CONSTRAINT UQ_SESION_ROL
            UNIQUE (SESION_PER_ID, SESION_ROL_ID)
    ); 
END
GO


IF OBJECT_ID('DBO.CAT_DESCUENTOS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.CAT_DESCUENTOS_TB(
	    CAT_DESC_ID INT IDENTITY(1,1), -- PK
        CAT_DESC_Nombre VARCHAR(75) NOT NULL, -- Navideño, Viernes Negro, Cierre Temporada, San Valentín, Sin Descuento, otros... N/A
        CAT_DESC_Estado BIT NOT NULL
            CONSTRAINT DF_CAT_DESC_Estado
                DEFAULT (1),

        -- PRIMARY KEY

        CONSTRAINT PK_CAT_DESCUENTOS_TB
            PRIMARY KEY(CAT_DESC_ID),

        -- CHECKS

        CONSTRAINT CK_CAT_DESC_Nombre
            CHECK(LEN(TRIM(CAT_DESC_Nombre)) > 0
                    AND CAT_DESC_Nombre NOT LIKE ' %'
                    AND CAT_DESC_Nombre NOT LIKE ' %'
                    AND CAT_DESC_Nombre NOT LIKE '%  %'),

        -- UNIQUES

        CONSTRAINT UQ_CAT_DESC_Nombre
            UNIQUE (CAT_DESC_Nombre)
    ); 
END
GO


IF OBJECT_ID('DBO.DESCUENTOS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.DESCUENTOS_TB(
	    DESC_ID INT IDENTITY(1,1), -- PK
        DESC_NombreComercial VARCHAR(100) NOT NULL, -- Nombre Comercial que ve el cliente
        DESC_Descripcion VARCHAR(175) NOT NULL,   -- N/A Si no hay descuento 
        DESC_CAT_DESC_ID INT NOT NULL, -- FK  
        DESC_DescuentoPct DECIMAL (5,2) NOT NULL -- 0.00 Si no hay descuento
            CONSTRAINT DF_DESC_DescuentoPct
                DEFAULT (0.00),
        DESC_FechaInicio DATE NOT NULL,
        DESC_FechaFin DATE NOT NULL,
        DESC_Estado BIT NOT NULL
            CONSTRAINT DF_DESC_Estado
                DEFAULT (1),

        -- PRIMARY KEY

        CONSTRAINT PK_DESCUENTOS_TB
            PRIMARY KEY (DESC_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_DESCUENTOS_CAT_DESC_ID 
            FOREIGN KEY (DESC_CAT_DESC_ID)
                REFERENCES CAT_DESCUENTOS_TB(CAT_DESC_ID),

        -- CHECKS

        CONSTRAINT CK_DESC_NombreComercial
            CHECK (LEN(TRIM(DESC_NombreComercial)) > 0
                    AND DESC_NombreComercial NOT LIKE ' %'
                    AND DESC_NombreComercial NOT LIKE '% '
                    AND DESC_NombreComercial NOT LIKE '%  %'),

        CONSTRAINT CK_DESC_Descripcion
            CHECK (LEN(TRIM(DESC_Descripcion)) > 0
                    AND DESC_Descripcion NOT LIKE ' %'
                    AND DESC_Descripcion NOT LIKE '% '
                    AND DESC_Descripcion NOT LIKE '%  %'),

        CONSTRAINT CK_DESC_DescuentoPct
            CHECK (DESC_DescuentoPct BETWEEN 0.00 AND 100.00),

        CONSTRAINT CK_FECHAS
            CHECK (DESC_FechaFin > DESC_FechaInicio)
    ); 
END
GO


IF OBJECT_ID('DBO.PROVEEDORES_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.PROVEEDORES_TB(
	    PRV_ID INT IDENTITY(1,1), -- PK
        PRV_PER_ID INT NOT NULL, -- FK
        PRV_Estado BIT NOT NULL
            CONSTRAINT DF_PRV_Estado
                DEFAULT(1),

        -- PRIMARY KEY

        CONSTRAINT PK_PROVEEDORES_TB
            PRIMARY KEY (PRV_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_PROVEEDORES_PER_ID
            FOREIGN KEY (PRV_PER_ID)
                REFERENCES PERSONAS_TB (PER_ID),

        -- UNIQUES

        CONSTRAINT UQ_PRV_PER_ID
            UNIQUE(PRV_PER_ID)
    ); 
END
GO


IF OBJECT_ID('DBO.MARCAS_PRODUCTOS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.MARCAS_PRODUCTOS_TB(
	    MARC_PRD_ID INT IDENTITY(1,1), -- PK
        MARC_PRD_Nombre VARCHAR(75) NOT NULL, -- Samsung, LG, Xiomi, Apple, HP, Sony, ASUS
        MARC_PRD_Estado BIT NOT NULL
            CONSTRAINT DF_MARC_PRD_Estado
                DEFAULT(1),

        -- PRIMARY KEY

        CONSTRAINT PK_MARCAS_PRODUCTOS_TB
            PRIMARY KEY (MARC_PRD_ID),

        -- CHECKS

        CONSTRAINT CK_MARC_PRD_Nombre
            CHECK(LEN(TRIM(MARC_PRD_Nombre)) > 0
                    AND MARC_PRD_Nombre NOT LIKE ' %'
                    AND MARC_PRD_Nombre NOT LIKE '% '
                    AND MARC_PRD_Nombre NOT LIKE '%  %'),

        -- UNIQUES

        CONSTRAINT UQ_MARC_PRD_Nombre
            UNIQUE (MARC_PRD_Nombre)
    ); 
END
GO


IF OBJECT_ID('DBO.TIPOS_PRODUCTOS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.TIPOS_PRODUCTOS_TB(
	    TIPO_PRD_ID INT IDENTITY(1,1), -- PK
        TIPO_PRD_Nombre VARCHAR(75) NOT NULL, -- Lavadora, Teléfono, Tablet, Computadora, Pantalla, PlayStation 5
        TIPO_PRD_Estado BIT NOT NULL
            CONSTRAINT DF_TIPO_PRD_Estado
                DEFAULT(1),

        -- PRIMARY KEY

        CONSTRAINT PK_TIPOS_PRODUCTOS_TB
            PRIMARY KEY (TIPO_PRD_ID),

        -- CHECKS

        CONSTRAINT CK_TIPO_PRD_Nombre
            CHECK(LEN(TRIM(TIPO_PRD_Nombre)) > 0
                    AND TIPO_PRD_Nombre NOT LIKE ' %'
                    AND TIPO_PRD_Nombre NOT LIKE '% '
                    AND TIPO_PRD_Nombre NOT LIKE '%  %'),

        -- UNIQUES

        CONSTRAINT UQ_TIPO_PRD_Nombre
            UNIQUE (TIPO_PRD_Nombre)
    ); 
END
GO


IF OBJECT_ID('DBO.PRODUCTOS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.PRODUCTOS_TB(
	    PRD_ID INT IDENTITY(1,1), -- PK
        PRD_RutaImagen VARCHAR(275) NOT NULL,
        PRD_Descripcion VARCHAR(150) NOT NULL,
        PRD_TIPO_PRD_ID INT NOT NULL, -- FK
        PRD_MARC_PRD_ID INT NOT NULL, -- FK
        PRD_PRV_ID INT NOT NULL, -- FK
        PRD_DESC_ID INT NULL -- FK
            CONSTRAINT DF_PRD_DESC_ID
                DEFAULT (NULL),
	    PRD_PrecioCompra DECIMAL(10,2) NOT NULL,
	    PRD_PrecioVenta DECIMAL(10,2) NOT NULL,
	    PRD_Estado BIT NOT NULL
            CONSTRAINT DF_PRD_Estado
                DEFAULT (1),

        -- PRIMARY KEY

        CONSTRAINT PK_PRODUCTOS_TB
            PRIMARY KEY (PRD_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_PRODUCTOS_TIPO_PRD_ID
            FOREIGN KEY (PRD_TIPO_PRD_ID)
                REFERENCES TIPOS_PRODUCTOS_TB(TIPO_PRD_ID),
        
        CONSTRAINT FK_PRODUCTOS_MARC_PRD_ID
            FOREIGN KEY (PRD_MARC_PRD_ID)
                REFERENCES MARCAS_PRODUCTOS_TB(MARC_PRD_ID),

        CONSTRAINT FK_PRODUCTOS_PRV_ID
            FOREIGN KEY (PRD_PRV_ID)
                REFERENCES PROVEEDORES_TB(PRV_ID),

        CONSTRAINT FK_PRODUCTOS_DESC_ID
            FOREIGN KEY (PRD_DESC_ID)
                REFERENCES DESCUENTOS_TB(DESC_ID),

        -- CHECKS

        CONSTRAINT CK_PRD_RutaImagen
            CHECK(LEN(TRIM(PRD_RutaImagen)) > 0
                    AND PRD_RutaImagen NOT LIKE ' %'
                    AND PRD_RutaImagen NOT LIKE '% '
                    AND PRD_RutaImagen NOT LIKE '%  %'),

        CONSTRAINT CK_PRD_Descripcion
            CHECK(LEN(TRIM(PRD_Descripcion)) > 0
                    AND PRD_Descripcion NOT LIKE ' %'
                    AND PRD_Descripcion NOT LIKE '% '
                    AND PRD_Descripcion NOT LIKE '%  %'),

        CONSTRAINT CK_PRD_PrecioCompra
            CHECK(PRD_PrecioCompra >= 0.00),

        CONSTRAINT CK_PRD_PrecioVenta
            CHECK(PRD_PrecioVenta > 0.00),

        CONSTRAINT CK_Precios
            CHECK(PRD_PrecioVenta >= PRD_PrecioCompra)
    ); 
END
GO


IF OBJECT_ID('DBO.UBI_INVENTARIOS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.UBI_INVENTARIOS_TB(
	    UBI_INV_ID INT IDENTITY(1,1),
        UBI_INV_Nombre VARCHAR(75) NOT NULL, -- XSTORE BODEGA CENTRAL, XSTORE CARTAGO, XSTORE SAN JOSÉ
        UBI_INV_Estado BIT NOT NULL
            CONSTRAINT DF_UBI_INV_Estado
                DEFAULT (1),

        -- PRIMARY KEY

        CONSTRAINT PK_UBICACION_INVENTARIO_TB
            PRIMARY KEY(UBI_INV_ID),
        
        -- CHECKS

        CONSTRAINT CK_UBI_INV_Nombre
            CHECK(LEN(TRIM(UBI_INV_Nombre)) > 0
                   AND UBI_INV_Nombre NOT LIKE ' %'
                   AND UBI_INV_Nombre NOT LIKE '% '
                   AND UBI_INV_Nombre NOT LIKE '%  %'),

        -- UNIQUES

        CONSTRAINT UQ_UBI_INV_Nombre
            UNIQUE(UBI_INV_Nombre)
    ); 
END
GO


IF OBJECT_ID('DBO.INVENTARIOS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.INVENTARIOS_TB(
	    INV_ID INT IDENTITY(1,1), -- PK
        INV_UBI_INV_ID INT NOT NULL, -- FK
        INV_PRD_ID INT NOT NULL, -- FK
	    INV_StockMinimo INT NOT NULL,
	    INV_StockActual INT NOT NULL,
	    INV_Estado BIT NOT NULL
            CONSTRAINT DF_INV_Estado
                DEFAULT (1),
        
        -- PRIMARY KEY

        CONSTRAINT PK_INVENTARIO_TB
            PRIMARY KEY (INV_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_INVENTARIO_UBI_INV_ID
            FOREIGN KEY (INV_UBI_INV_ID)
                REFERENCES UBI_INVENTARIOS_TB (UBI_INV_ID),

        CONSTRAINT FK_INVENTARIO_PRD_ID
            FOREIGN KEY (INV_PRD_ID)
                REFERENCES PRODUCTOS_TB (PRD_ID),

        -- CHECKS

        CONSTRAINT CK_INV_StockMinimo
            CHECK (INV_StockMinimo >= 0),

        CONSTRAINT CK_INV_StockActual
            CHECK (INV_StockActual >= 0),

        -- UNIQUE

        CONSTRAINT UQ_INV_UbicacionProductos
            UNIQUE (INV_UBI_INV_ID, INV_PRD_ID)

    );
END
GO


IF OBJECT_ID('DBO.ENC_FACTURAS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.ENC_FACTURAS_TB(
	    ENC_FAC_ID INT IDENTITY(1,1), -- PK
        ENC_FAC_Numero VARCHAR(75) NOT NULL,
        ENC_FAC_PER_ID INT NOT NULL, -- FK
        ENC_FAC_FechaHora DATETIME2 NOT NULL
            CONSTRAINT DF_ENC_FAC_FechaHora
                DEFAULT (SYSDATETIME()),
        ENC_FAC_Subtotal DECIMAL(10,2) NOT NULL,
        ENC_FAC_DescuentoTotal DECIMAL(10,2) NOT NULL
            CONSTRAINT DF_ENC_FAC_DescuentoTotal
                DEFAULT (0.00), -- No siempre se hacen descuentos
        ENC_FAC_ImpuestoPct DECIMAL(5,2) NOT NULL
            CONSTRAINT DF_ENC_FAC_ImpuestoPct
                DEFAULT (13.00), -- 13%
	    ENC_FAC_ImpuestoTotal DECIMAL(10,2) NOT NULL,
        ENC_FAC_CostoEnvio DECIMAL(10,2) NOT NULL
            CONSTRAINT DF_ENC_FAC_CostoEnvio
                DEFAULT (0.00), -- No siempre se hace entrega
	    ENC_FAC_Total DECIMAL(10,2) NOT NULL,

        -- PRIMARY KEY

        CONSTRAINT PK_ENC_FACTURAS_TB
            PRIMARY KEY (ENC_FAC_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_ENC_FACTURAS_PER_ID
            FOREIGN KEY (ENC_FAC_PER_ID)
                REFERENCES PERSONAS_TB(PER_ID),

        -- CHECKS

        CONSTRAINT CK_ENC_FAC_Numero
            CHECK (LEN(TRIM(ENC_FAC_Numero)) > 0
                    AND ENC_FAC_Numero NOT LIKE ' %'
                    AND ENC_FAC_Numero NOT LIKE '% '
                    AND ENC_FAC_Numero NOT LIKE '%  %'),

        CONSTRAINT CK_ENC_FAC_Subtotal
            CHECK (ENC_FAC_Subtotal >= 0.00),

        CONSTRAINT CK_ENC_FAC_DescuentoTotal
            CHECK (ENC_FAC_DescuentoTotal >= 0.00),

        CONSTRAINT CK_ENC_FAC_ImpuestoPct
            CHECK (ENC_FAC_ImpuestoPct BETWEEN 0.00 AND 100.00),

        CONSTRAINT CK_ENC_FAC_ImpuestoTotal
            CHECK (ENC_FAC_ImpuestoTotal >= 0),

        CONSTRAINT CK_ENC_FAC_CostoEnvio
            CHECK (ENC_FAC_CostoEnvio >= 0),

        CONSTRAINT CK_ENC_FAC_Total
            CHECK (ENC_FAC_Total >= 0),

        -- UNIQUES

        CONSTRAINT UQ_ENC_FAC_Numero
            UNIQUE (ENC_FAC_Numero)
    ); 
END
GO


IF OBJECT_ID('DBO.ESTADOS_ENTREGAS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.ESTADOS_ENTREGAS_TB(
	    EST_ENT_ID INT IDENTITY(1,1), -- PK
        EST_ENT_Nombre VARCHAR(50) NOT NULL,
        EST_ENT_Estado BIT NOT NULL
            CONSTRAINT DF_EST_ENT_Estado
                DEFAULT (1),

        -- PRIMARY KEY

        CONSTRAINT PK_ESTADOS_ENTREGAS_TB
            PRIMARY KEY (EST_ENT_ID),
        
        -- CHECKS

        CONSTRAINT CK_EST_ENT_Nombre
            CHECK (LEN(TRIM(EST_ENT_Nombre)) > 0
                    AND EST_ENT_Nombre NOT LIKE ' %'
                    AND EST_ENT_Nombre NOT LIKE '% '
                    AND EST_ENT_Nombre NOT LIKE '%  %'),

        -- UNIQUES

        CONSTRAINT UQ_EST_ENT_Nombre
            UNIQUE (EST_ENT_Nombre)
    ); 
END
GO


IF OBJECT_ID('DBO.ENC_ENTREGAS_CLIENTES_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.ENC_ENTREGAS_CLIENTES_TB(
	    ENC_ENT_CLI_ID INT IDENTITY(1,1), -- PK
        ENC_ENT_CLI_ENC_FAC_ID INT NOT NULL, --FK
	    ENC_ENT_CLI_FechaEntrega DATE NOT NULL,
	    ENC_ENT_CLI_DireccionEntrega VARCHAR(150) NOT NULL,
	    ENC_ENT_CLI_Observaciones VARCHAR(150) NULL,
	    ENC_ENT_CLI_EST_ENT_ID INT NOT NULL, -- FK

        -- PRIMARY KEY

        CONSTRAINT PK_ENC_ENTREGAS_CLIENTES_TB
            PRIMARY KEY (ENC_ENT_CLI_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_ENC_ENTREGAS_CLIENTES_ENC_FAC_ID
            FOREIGN KEY (ENC_ENT_CLI_ENC_FAC_ID)
                REFERENCES ENC_FACTURAS_TB (ENC_FAC_ID),

        CONSTRAINT FK_ENC_ENTREGAS_CLIENTES_EST_ENT_ID
            FOREIGN KEY (ENC_ENT_CLI_EST_ENT_ID)
                REFERENCES ESTADOS_ENTREGAS_TB (EST_ENT_ID),

        -- CHECKS

        CONSTRAINT CK_ENC_ENT_CLI_DireccionEntrega
            CHECK (LEN(TRIM(ENC_ENT_CLI_DireccionEntrega)) > 0
                    AND ENC_ENT_CLI_DireccionEntrega NOT LIKE ' %'
                    AND ENC_ENT_CLI_DireccionEntrega NOT LIKE '% '
                    AND ENC_ENT_CLI_DireccionEntrega NOT LIKE '%  %'),

        CONSTRAINT CK_ENC_ENT_CLI_Observaciones
            CHECK (ENC_ENT_CLI_Observaciones IS NULL
                    OR (LEN(TRIM(ENC_ENT_CLI_Observaciones)) > 5
                        AND ENC_ENT_CLI_Observaciones NOT LIKE ' %'
                        AND ENC_ENT_CLI_Observaciones NOT LIKE '% '
                        AND ENC_ENT_CLI_Observaciones NOT LIKE '%  %')),

        -- UNIQUES

        CONSTRAINT UQ_ENC_ENT_CLI_ENC_FAC_ID 
            UNIQUE (ENC_ENT_CLI_ENC_FAC_ID)
    ); 
END
GO


IF OBJECT_ID('DBO.DET_FACTURAS_TB', 'U') IS NULL
BEGIN
    CREATE TABLE DBO.DET_FACTURAS_TB(
	    DET_FAC_ID INT IDENTITY(1,1), -- PK
	    DET_FAC_ENC_FAC_ID INT NOT NULL, -- FK
	    DET_FAC_PRD_ID INT NOT NULL, -- FK
	    DET_FAC_Cantidad INT NOT NULL, 
	    DET_FAC_PrecioUnitario DECIMAL(10,2) NOT NULL,
	    DET_FAC_DESC_ID INT NOT NULL, --FK
	    DET_FAC_DescuentoMonto DECIMAL(10,2) NOT NULL,
	    DET_FAC_SubtotalLinea DECIMAL(10,2) NOT NULL,
	    DET_FAC_TotalLinea DECIMAL(10,2) NOT NULL,

        -- PRIMARY KEY

        CONSTRAINT PK_DET_FACTURAS_TB
            PRIMARY KEY (DET_FAC_ID),

        -- FOREIGN KEYS

        CONSTRAINT FK_DET_FACTURAS_ENC_FAC_ID
            FOREIGN KEY (DET_FAC_ENC_FAC_ID)
                REFERENCES ENC_FACTURAS_TB (ENC_FAC_ID),

        CONSTRAINT FK_DET_FACTURAS_PRD_ID
            FOREIGN KEY (DET_FAC_PRD_ID)
                REFERENCES PRODUCTOS_TB (PRD_ID),

        CONSTRAINT FK_DET_FACTURAS_DESC_ID
            FOREIGN KEY (DET_FAC_DESC_ID)
                REFERENCES DESCUENTOS_TB (DESC_ID),

        -- CHECKS

        CONSTRAINT CK_DET_FAC_Cantidad
            CHECK (DET_FAC_Cantidad > 0),

        CONSTRAINT CK_DET_FAC_PrecioUnitario
            CHECK (DET_FAC_PrecioUnitario >= 0),

        CONSTRAINT CK_DET_FAC_DescuentoMonto
            CHECK (DET_FAC_DescuentoMonto >= 0),

        CONSTRAINT CK_DET_FAC_SubtotalLinea
            CHECK (DET_FAC_SubtotalLinea >= 0),

        CONSTRAINT CK_DET_FAC_ControlDescuentos
            CHECK (DET_FAC_DescuentoMonto <= DET_FAC_SubtotalLinea),

        CONSTRAINT CK_DET_FAC_TotalLinea
            CHECK (DET_FAC_TotalLinea >= 0),

        -- UNIQUES

        CONSTRAINT UQ_DET_FAC_ENC_FAC_PRD
            UNIQUE (DET_FAC_ENC_FAC_ID, DET_FAC_PRD_ID)
    ); 
END
GO
