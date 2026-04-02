------------------------------
--- ****** DATABASE ****** ---
IF DB_ID('XSTORE') IS NULL
BEGIN
    CREATE DATABASE XSTORE;
END
GO

USE XSTORE;
GO

---- ****** TRIGGERS ****** ----
CREATE OR ALTER TRIGGER DBO.BLOQUEAR_AUDITORIA_TR
ON DBO.AUDITORIAS_TB
INSTEAD OF UPDATE, DELETE 
AS
BEGIN
 
    SET NOCOUNT ON;
    
    DECLARE @Accion NVARCHAR(10) = '';
    
    IF EXISTS(SELECT 1 FROM deleted) AND EXISTS(SELECT 1 FROM inserted)
        SET @Accion = 'UPDATE';
    ELSE
        SET @Accion = 'DELETE';
 
    RAISERROR ('SEGURIDAD: La tabla de Auditoría es INMUTABLE. No se permite [%s].', 16, 1, @Accion);
 
END;
GO


CREATE OR ALTER TRIGGER DBO.REGISTRAR_ROL_TR
ON DBO.ROLES_TB
AFTER INSERT
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL 
        SET @Persona_ID = 1; -- Fallback al sistema si no hay context

    INSERT INTO DBO.AUDITORIAS_TB(
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT 
        @Persona_ID,
        'INSERT',
        'ROLES_TB',
        I.ROL_ID,
        CASE 
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_ROL_TR.'
            ELSE 
                'Se usó REGISTRAR_ROL_TR.'
        END,
        NULL,
        '[ Nombre: ' + I.ROL_Nombre + ' | Accesos: ' + I.ROL_Accesos + ' | Estado: ' + CASE WHEN I.ROL_ESTADO = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM INSERTED I
END;
GO



CREATE OR ALTER TRIGGER DBO.MODIFICAR_ROL_TR
ON DBO.ROLES_TB
AFTER UPDATE
AS
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL 
        SET @Persona_ID = 1; -- Fallback al sistema si no hay context

    INSERT INTO DBO.AUDITORIAS_TB(
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT 
        @Persona_ID,
        'UPDATE',
        'ROLES_TB',
        I.ROL_ID,
        CASE 
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y MODIFICAR_ROL_TR.'
            ELSE 
                'Se usó MODIFICAR_ROL_TR.'
        END,
        '[ Nombre: ' + D.ROL_Nombre + ' | Accesos: ' + D.ROL_Accesos + ' | Estado: ' + CASE WHEN D.ROL_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Nombre: ' + I.ROL_Nombre + ' | Accesos: ' + I.ROL_Accesos + ' | Estado: ' + CASE WHEN I.ROL_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.ROL_ID = I.ROL_ID;
END;
GO



CREATE OR ALTER TRIGGER DBO.REGISTRAR_SESION_TR
ON DBO.SESIONES_TB
AFTER INSERT
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT     = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL 
        SET @Persona_ID = 1; -- Fallback al sistema si no hay contexto

    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT 
        @Persona_ID,
        'INSERT',
        'SESIONES_TB',
        I.SESION_ID,
        CASE 
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_SESION_TR.'
            ELSE
                'Se usó REGISTRAR_SESION_TR.'
        END,
        NULL,
        '[ Persona: ' + P.PER_NombreCompleto + ' | Usuario: ' + I.SESION_NombreUsuario + ' | Contraseña: ****' + 
        ' | Rol: ' + R.ROL_Nombre + ' | Estado: ' + CASE WHEN I.SESION_Estado = 1 THEN 'Activo' Else 'Inactivo' END + ' ]'
    FROM INSERTED I
    INNER JOIN PERSONAS_TB P
        ON I.SESION_PER_ID = P.PER_ID
    INNER JOIN ROLES_TB R
        ON I.SESION_ROL_ID = R.ROL_ID
END;
GO


CREATE OR ALTER TRIGGER DBO.REGISTRAR_TIPO_PRODUCTO_TR
ON DBO.TIPOS_PRODUCTOS_TB 
AFTER INSERT
AS
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT     = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL 
        SET @Persona_ID = 1; -- Fallback al sistema si no hay contexto

    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'INSERT',
        'TIPOS_PRODUCTOS_TB',
        I.TIPO_PRD_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_TIPO_PRODUCTO_TR.'
            ELSE
                'Se usó REGISTRAR_TIPO_PRODUCTO_TR.'
        END,
        NULL,
        '[ Nombre: ' + I.TIPO_PRD_Nombre + ' | Estado: ' + CASE WHEN I.TIPO_PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM INSERTED I
END;
GO



CREATE OR ALTER TRIGGER DBO.MODIFICAR_TIPO_PRODUCTO_TR
ON DBO.TIPOS_PRODUCTOS_TB 
AFTER UPDATE
AS
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1; -- Fallback al sistema si no hay context

    INSERT INTO DBO.AUDITORIAS_TB(
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT 
        @Persona_ID,
        'UPDATE',
        'TIPOS_PRODUCTOS_TB',
        I.TIPO_PRD_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y MODIFICAR_TIPO_PRODUCTO_TR.'
            ELSE
                'Se usó MODIFICAR_TIPO_PRODUCTO_TR.'
        END,
        '[ Nombre: ' + D.TIPO_PRD_Nombre + ' | Estado: ' + CASE WHEN D.TIPO_PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Nombre: ' + I.TIPO_PRD_Nombre + ' | Estado: ' + CASE WHEN I.TIPO_PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.TIPO_PRD_ID = I.TIPO_PRD_ID;
END;
GO



CREATE OR ALTER TRIGGER DBO.REGISTRAR_MARCA_PRODUCTO_TR
ON DBO.MARCAS_PRODUCTOS_TB
AFTER INSERT
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL
        SET @Persona_ID = 1; -- Fallback al sistema si no hay contexto
 
    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'INSERT',
        'MARCAS_PRODUCTOS_TB',
        I.MARC_PRD_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_MARCA_PRODUCTO_TR.'
            ELSE
                'Se usó REGISTRAR_MARCA_PRODUCTO_TR.'
        END,
        NULL,
        '[ Nombre: ' + I.MARC_PRD_Nombre + ' | Estado: ' + CASE WHEN I.MARC_PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM INSERTED I;
 
END;
GO



CREATE OR ALTER TRIGGER DBO.MODIFICAR_MARCA_PRODUCTO_TR
ON DBO.MARCAS_PRODUCTOS_TB
AFTER UPDATE
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL
        SET @Persona_ID = 1; -- Fallback al sistema si no hay contexto
 
    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'UPDATE',
        'MARCAS_PRODUCTOS_TB',
        I.MARC_PRD_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y MODIFICAR_MARCA_PRODUCTO_TR.'
            ELSE
                'Se usó MODIFICAR_MARCA_PRODUCTO_TR.'
        END,
        '[ Nombre: ' + D.MARC_PRD_Nombre + ' | Estado: ' + CASE WHEN D.MARC_PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Nombre: ' + I.MARC_PRD_Nombre + ' | Estado: ' + CASE WHEN I.MARC_PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.MARC_PRD_ID = I.MARC_PRD_ID;
END;
GO



CREATE OR ALTER TRIGGER DBO.REGISTRAR_UBICACION_TR
ON DBO.UBI_INVENTARIOS_TB
AFTER INSERT
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;
 
    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'INSERT',
        'UBI_INVENTARIOS_TB',
        I.UBI_INV_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_UBICACION_TR.'
            ELSE
                'Se usó REGISTRAR_UBICACION_TR.'
        END,
        NULL,
        '[ Nombre: ' + I.UBI_INV_Nombre + ' | Estado: ' + CASE WHEN I.UBI_INV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM INSERTED I;
END;
GO
 

 
CREATE OR ALTER TRIGGER DBO.MODIFICAR_UBICACION_TR
ON DBO.UBI_INVENTARIOS_TB
AFTER UPDATE
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;
 
    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'UPDATE',
        'UBI_INVENTARIOS_TB',
        I.UBI_INV_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y MODIFICAR_UBICACION_TR.'
            ELSE
                'Se usó MODIFICAR_UBICACION_TR.'
        END,
        '[ Nombre: ' + D.UBI_INV_Nombre + ' | Estado: ' + CASE WHEN D.UBI_INV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Nombre: ' + I.UBI_INV_Nombre + ' | Estado: ' + CASE WHEN I.UBI_INV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.UBI_INV_ID = I.UBI_INV_ID;
END;
GO



CREATE OR ALTER TRIGGER DBO.REGISTRAR_CAT_DESCUENTO_TR
ON DBO.CAT_DESCUENTOS_TB
AFTER INSERT
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'INSERT',
        'CAT_DESCUENTOS_TB',
        I.CAT_DESC_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_CAT_DESCUENTO_TR.'
            ELSE
                'Se usó REGISTRAR_CAT_DESCUENTO_TR.'
        END,
        NULL,
        '[ Nombre: ' + I.CAT_DESC_Nombre + ' | Estado: ' + CASE WHEN I.CAT_DESC_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM INSERTED I;

END;
GO



CREATE OR ALTER TRIGGER DBO.MODIFICAR_CAT_DESCUENTO_TR
ON DBO.CAT_DESCUENTOS_TB
AFTER UPDATE
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'UPDATE',
        'CAT_DESCUENTOS_TB',
        I.CAT_DESC_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y MODIFICAR_CAT_DESCUENTO_TR.'
            ELSE
                'Se usó MODIFICAR_CAT_DESCUENTO_TR.'
        END,
        '[ Nombre: ' + D.CAT_DESC_Nombre + ' | Estado: ' + CASE WHEN D.CAT_DESC_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Nombre: ' + I.CAT_DESC_Nombre + ' | Estado: ' + CASE WHEN I.CAT_DESC_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.CAT_DESC_ID = I.CAT_DESC_ID;
END;
GO


CREATE OR ALTER TRIGGER DBO.REGISTRAR_TIPO_PERSONA_TR
ON DBO.TIPOS_PERSONAS_TB
AFTER INSERT
AS
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'INSERT',
        'TIPOS_PERSONAS_TB',
        I.TIPO_PER_ID,
        CASE
            WHEN @Origen IS NOT NULL 
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_TIPO_PERSONA_TR.'
            ELSE 
                'Se usó REGISTRAR_TIPO_PERSONA_TR.'
        END,
        NULL,
        '[ Nombre: ' + I.TIPO_PER_Nombre + 
        ' | Descuento %: ' + CONVERT(VARCHAR(30), I.TIPO_PER_DescuentoPct) + 
        '% | Monto Meta: ' + CONVERT(VARCHAR(30), I.TIPO_PER_MontoMeta) + 
        ' | Estado: ' + CASE WHEN I.TIPO_PER_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM INSERTED I;
END;
GO



CREATE OR ALTER TRIGGER DBO.MODIFICAR_TIPO_PERSONA_TR
ON DBO.TIPOS_PERSONAS_TB
AFTER UPDATE
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'UPDATE',
        'TIPOS_PERSONAS_TB',
        I.TIPO_PER_ID,
        CASE
            WHEN @Origen IS NOT NULL THEN 'Se usó ' + @Origen + ' y MODIFICAR_TIPO_PERSONA_TR.'
            ELSE 'Se usó MODIFICAR_TIPO_PERSONA_TR.'
        END,
        '[ Nombre: ' + D.TIPO_PER_Nombre + 
        ' | Descuento %: ' + CONVERT(VARCHAR(30), D.TIPO_PER_DescuentoPct) + 
        '% | Monto Meta: ' + CONVERT(VARCHAR(30), D.TIPO_PER_MontoMeta) + 
        ' | Estado: ' + CASE WHEN D.TIPO_PER_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Nombre: ' + I.TIPO_PER_Nombre + 
        ' | Descuento %: ' + CONVERT(VARCHAR(30), I.TIPO_PER_DescuentoPct) + 
        '% | Monto Meta: ' + CONVERT(VARCHAR(30), I.TIPO_PER_MontoMeta) + 
        ' | Estado: ' + CASE WHEN I.TIPO_PER_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.TIPO_PER_ID = I.TIPO_PER_ID;
END;
GO



CREATE OR ALTER TRIGGER DBO.REGISTRAR_PERSONA_TR
ON DBO.PERSONAS_TB
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    IF @Persona_ID = 0
        SELECT @Persona_ID = I.PER_ID 
        FROM INSERTED I

    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'INSERT',
        'PERSONAS_TB',
        I.PER_ID,
        CASE
            WHEN @Origen IS NOT NULL 
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_PERSONA_TR.'
            ELSE 
                'Se usó REGISTRAR_PERSONA_TR.'
        END,
        NULL,
        '[ Identificacion: ' + I.PER_Identificacion + 
        ' | Nombre Completo: ' + I.PER_NombreCompleto + 
        ' | Teléfono: ' + COALESCE(I.PER_Telefono, 'N/A') + 
        ' | Correo: ' + COALESCE(I.PER_Correo, 'N/A') + 
        ' | Dirección: ' + COALESCE(I.PER_Direccion, 'N/A') + 
        ' | Tipo Persona: ' + TP.TIPO_PER_Nombre + 
        ' | Estado: ' + CASE WHEN I.PER_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM INSERTED I
        INNER JOIN TIPOS_PERSONAS_TB TP
            ON I.PER_TIPO_PER_ID = TP.TIPO_PER_ID;
END;
GO



CREATE OR ALTER TRIGGER DBO.MODIFICAR_PERSONA_TR
ON DBO.PERSONAS_TB
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;
 
    INSERT INTO DBO.AUDITORIAS_TB
    (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'UPDATE',
        'PERSONAS_TB',
        I.PER_ID,
        CASE
            WHEN @Origen IS NOT NULL THEN 'Se usó ' + @Origen + ' y MODIFICAR_PERSONA_TR.'
            ELSE 'Se usó MODIFICAR_PERSONA_TR.'
        END,
        '[ Identificacion: ' + D.PER_Identificacion + 
        ' | Nombre Completo: ' + D.PER_NombreCompleto + 
        ' | Teléfono: ' + COALESCE(D.PER_Telefono, 'N/A') + 
        ' | Correo: ' + COALESCE(D.PER_Correo, 'N/A') + 
        ' | Dirección: ' + COALESCE(D.PER_Direccion, 'N/A') + 
        ' | Tipo Persona: ' + TP.TIPO_PER_Nombre + 
        ' | Estado: ' + CASE WHEN D.PER_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Identificacion: ' + I.PER_Identificacion + 
        ' | Nombre Completo: ' + I.PER_NombreCompleto + 
        ' | Teléfono: ' + COALESCE(I.PER_Telefono, 'N/A') + 
        ' | Correo: ' + COALESCE(I.PER_Correo, 'N/A') + 
        ' | Dirección: ' + COALESCE(I.PER_Direccion, 'N/A') + 
        ' | Tipo Persona: ' + TP.TIPO_PER_Nombre + 
        ' | Estado: ' + CASE WHEN I.PER_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.PER_ID = I.PER_ID
    INNER JOIN TIPOS_PERSONAS_TB TP
        ON I.PER_TIPO_PER_ID = TP.TIPO_PER_ID;
END;
GO



CREATE OR ALTER TRIGGER DBO.REGISTRAR_PROVEEDOR_TR
ON DBO.PROVEEDORES_TB
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    INSERT INTO DBO.AUDITORIAS_TB (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'INSERT',
        'PROVEEDORES_TB',
        I.PRV_ID,
        CASE
            WHEN @Origen IS NOT NULL 
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_PROVEEDOR_TR.'
            ELSE 
                'Se usó REGISTRAR_PROVEEDOR_TR.'
        END,
        NULL,
        '[ Proveedor : ' + P.PER_NombreCompleto + 
        ' | Estado: ' + CASE WHEN I.PRV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM INSERTED I
        INNER JOIN PERSONAS_TB P
            ON I.PRV_PER_ID = P.PER_ID;
END;
GO



CREATE OR ALTER TRIGGER DBO.MODIFICAR_PROVEEDOR_TR
ON DBO.PROVEEDORES_TB
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    INSERT INTO DBO.AUDITORIAS_TB
    (
        AUD_PER_ID,
        AUD_Accion,
        AUD_TablaAfectada,
        AUD_FilaAfectada,
        AUD_Descripcion,
        AUD_Antes,
        AUD_Despues
    )
    SELECT
        @Persona_ID,
        'UPDATE',
        'PROVEEDORES_TB',
        I.PRV_ID,
        CASE
            WHEN @Origen IS NOT NULL THEN 'Se usó ' + @Origen + ' y MODIFICAR_PROVEEDOR_TR.'
            ELSE 'Se usó MODIFICAR_PROVEEDOR_TR.'
        END,
        '[ Proveedor : ' + P.PER_NombreCompleto + 
        ' | Estado: ' + CASE WHEN D.PRV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Proveedor : ' + P.PER_NombreCompleto + 
        ' | Estado: ' + CASE WHEN I.PRV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.PRV_ID = I.PRV_ID
    INNER JOIN PERSONAS_TB P
        ON I.PRV_PER_ID = P.PER_ID;
END;
GO