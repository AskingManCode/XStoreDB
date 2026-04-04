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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO


CREATE OR ALTER TRIGGER DBO.MODIFICAR_SESION_TR
ON DBO.SESIONES_TB
AFTER UPDATE
AS
BEGIN 

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    BEGIN TRY
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
            'SESIONES_TB',
            I.SESION_ID,
            CASE
                WHEN @Origen IS NOT NULL
                    THEN 'Se usó ' + @Origen + ' y MODIFICAR_SESION_TR.'
                ELSE
                    'Se usó MODIFICAR_SESION_TR.'
            END,
            '[ Persona: ' + P.PER_NombreCompleto +
            ' | Usuario: ' + D.SESION_NombreUsuario +
            ' | Contraseña: ****' +
            ' | Rol: ' + R_OLD.ROL_Nombre +
            ' | Estado: ' + CASE WHEN D.SESION_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
            '[ Persona: ' + P.PER_NombreCompleto +
            ' | Usuario: ' + I.SESION_NombreUsuario +
            ' | Contraseña: ****' +
            ' | Rol: ' + R_NEW.ROL_Nombre +
            ' | Estado: ' + CASE WHEN I.SESION_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
        FROM DELETED D
        INNER JOIN INSERTED I
            ON D.SESION_ID = I.SESION_ID
        INNER JOIN DBO.PERSONAS_TB P
            ON I.SESION_PER_ID = P.PER_ID
        INNER JOIN DBO.ROLES_TB R_OLD
            ON D.SESION_ROL_ID = R_OLD.ROL_ID
        INNER JOIN DBO.ROLES_TB R_NEW
            ON I.SESION_ROL_ID = R_NEW.ROL_ID;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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
 
    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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
 
    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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
 
    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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
 
    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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
 
    BEGIN TRY
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
            'PERSONAS_TB',
            I.PER_ID,
            CASE
                WHEN @Origen IS NOT NULL 
                    THEN 'Se usó ' + @Origen + ' y MODIFICAR_PERSONA_TR.'
                ELSE 
                    'Se usó MODIFICAR_PERSONA_TR.'
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
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

    BEGIN TRY
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
            'PROVEEDORES_TB',
            I.PRV_ID,
            CASE
                WHEN @Origen IS NOT NULL 
                    THEN 'Se usó ' + @Origen + ' y MODIFICAR_PROVEEDOR_TR.'
                ELSE 
                    'Se usó MODIFICAR_PROVEEDOR_TR.'
            END,
            '[ Proveedor : ' + P_OLD.PER_NombreCompleto + 
            ' | Estado: ' + CASE WHEN D.PRV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
            '[ Proveedor : ' + P_NEW.PER_NombreCompleto + 
            ' | Estado: ' + CASE WHEN I.PRV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
            FROM DELETED D
            INNER JOIN INSERTED I 
                ON D.PRV_ID = I.PRV_ID
            INNER JOIN PERSONAS_TB P_NEW 
                ON I.PRV_PER_ID = P_NEW.PER_ID
            INNER JOIN PERSONAS_TB P_OLD 
                ON D.PRV_PER_ID = P_OLD.PER_ID;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO


CREATE OR ALTER TRIGGER DBO.REGISTRAR_ESTADO_ENTREGA_TR
ON DBO.ESTADOS_ENTREGAS_TB
AFTER INSERT
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;
 
    BEGIN TRY
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
            'ESTADOS_ENTREGAS_TB',
            I.EST_ENT_ID,
            CASE
                WHEN @Origen IS NOT NULL
                    THEN 'Se usó ' + @Origen + ' y REGISTRAR_ESTADO_ENTREGA_TR.'
                ELSE
                    'Se usó REGISTRAR_ESTADO_ENTREGA_TR.'
            END,
            NULL,
            '[ Nombre: ' + I.EST_ENT_Nombre + ' | Estado: ' + CASE WHEN I.EST_ENT_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
        FROM INSERTED I;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO


CREATE OR ALTER TRIGGER DBO.MODIFICAR_ESTADO_ENTREGA_TR
ON DBO.ESTADOS_ENTREGAS_TB
AFTER UPDATE
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));
 
    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;
 
    BEGIN TRY
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
            'ESTADOS_ENTREGAS_TB',
            I.EST_ENT_ID,
            CASE
                WHEN @Origen IS NOT NULL
                    THEN 'Se usó ' + @Origen + ' y MODIFICAR_ESTADO_ENTREGA_TR.'
                ELSE
                    'Se usó MODIFICAR_ESTADO_ENTREGA_TR.'
            END,
            '[ Nombre: ' + D.EST_ENT_Nombre + ' | Estado: ' + CASE WHEN D.EST_ENT_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
            '[ Nombre: ' + I.EST_ENT_Nombre + ' | Estado: ' + CASE WHEN I.EST_ENT_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
        FROM DELETED D
        INNER JOIN INSERTED I
            ON D.EST_ENT_ID = I.EST_ENT_ID;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO


CREATE OR ALTER TRIGGER DBO.REGISTRAR_DESCUENTO_TR
ON DBO.DESCUENTOS_TB
AFTER INSERT
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    BEGIN TRY
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
            'DESCUENTOS_TB',
            I.DESC_ID,
            CASE
                WHEN @Origen IS NOT NULL
                    THEN 'Se usó ' + @Origen + ' y REGISTRAR_DESCUENTO_TR.'
                ELSE
                    'Se usó REGISTRAR_DESCUENTO_TR.'
            END,
            NULL,
            '[ Nombre Comercial: ' + I.DESC_NombreComercial + 
            ' | Descripción: ' + I.DESC_Descripcion + 
            ' | Categoría: ' + C.CAT_DESC_Nombre +
            ' | Descuento: ' + CONVERT(VARCHAR(5), I.DESC_DescuentoPct) + '%' +
            ' | Fecha Inicio: ' + CONVERT(VARCHAR(10), I.DESC_FechaInicio, 120) +
            ' | Fecha Fin: ' + CONVERT(VARCHAR(10), I.DESC_FechaFin, 120) +
            ' | Estado: ' + CASE WHEN I.DESC_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
        FROM INSERTED I
        INNER JOIN DBO.CAT_DESCUENTOS_TB C
            ON I.DESC_CAT_DESC_ID = C.CAT_DESC_ID;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO


CREATE OR ALTER TRIGGER DBO.MODIFICAR_DESCUENTO_TR
ON DBO.DESCUENTOS_TB
AFTER UPDATE
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    BEGIN TRY
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
            'DESCUENTOS_TB',
            I.DESC_ID,
            CASE
                WHEN @Origen IS NOT NULL
                    THEN 'Se usó ' + @Origen + ' y MODIFICAR_DESCUENTO_TR.'
                ELSE
                    'Se usó MODIFICAR_DESCUENTO_TR.'
            END,
            '[ Nombre Comercial: ' + D.DESC_NombreComercial +
            ' | Descripción: '     + D.DESC_Descripcion +
            ' | Categoría: '       + C_OLD.CAT_DESC_Nombre +
            ' | Descuento: '       + CONVERT(VARCHAR(5), D.DESC_DescuentoPct) + '%' +
            ' | Fecha Inicio: '    + CONVERT(VARCHAR(10), D.DESC_FechaInicio, 120) +
            ' | Fecha Fin: '       + CONVERT(VARCHAR(10), D.DESC_FechaFin, 120) +
            ' | Estado: '          + CASE WHEN D.DESC_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
            '[ Nombre Comercial: ' + I.DESC_NombreComercial +
            ' | Descripción: '     + I.DESC_Descripcion +
            ' | Categoría: '       + C_NEW.CAT_DESC_Nombre +
            ' | Descuento: '       + CONVERT(VARCHAR(5), I.DESC_DescuentoPct) + '%' +
            ' | Fecha Inicio: '    + CONVERT(VARCHAR(10), I.DESC_FechaInicio, 120) +
            ' | Fecha Fin: '       + CONVERT(VARCHAR(10), I.DESC_FechaFin, 120) +
            ' | Estado: '          + CASE WHEN I.DESC_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
        FROM DELETED D
        INNER JOIN INSERTED I
            ON D.DESC_ID = I.DESC_ID
        INNER JOIN DBO.CAT_DESCUENTOS_TB C_OLD
            ON D.DESC_CAT_DESC_ID = C_OLD.CAT_DESC_ID
        INNER JOIN DBO.CAT_DESCUENTOS_TB C_NEW
            ON I.DESC_CAT_DESC_ID = C_NEW.CAT_DESC_ID;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO


CREATE OR ALTER TRIGGER DBO.REGISTRAR_PRODUCTO_TR
ON DBO.PRODUCTOS_TB
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    BEGIN TRY
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
            'PRODUCTOS_TB',
            I.PRD_ID,
            CASE
                WHEN @Origen IS NOT NULL
                    THEN 'Se usó ' + @Origen + ' y REGISTRAR_PRODUCTO_TR.'
                ELSE
                    'Se usó REGISTRAR_PRODUCTO_TR.'
            END,
            NULL,
            '[ Descripción: ' + I.PRD_Descripcion +
            ' | Tipo: ' + TP.TIPO_PRD_Nombre +
            ' | Marca: ' + MP.MARC_PRD_Nombre +
            ' | Proveedor: ' + P.PER_NombreCompleto +
            ' | P.Compra: ' + CONVERT(VARCHAR(15), I.PRD_PrecioCompra) +
            ' | P.Venta: ' + CONVERT(VARCHAR(15), I.PRD_PrecioVenta) +
            ' | Descuento: ' + ISNULL(D.DESC_NombreComercial, 'N/A') +
            ' | Estado: ' + CASE WHEN I.PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
        FROM INSERTED I
        INNER JOIN DBO.TIPOS_PRODUCTOS_TB TP
            ON I.PRD_TIPO_PRD_ID = TP.TIPO_PRD_ID
        INNER JOIN DBO.MARCAS_PRODUCTOS_TB MP
            ON I.PRD_MARC_PRD_ID = MP.MARC_PRD_ID
        INNER JOIN DBO.PROVEEDORES_TB PRV
            ON I.PRD_PRV_ID = PRV.PRV_ID
        INNER JOIN DBO.PERSONAS_TB P
            ON PRV.PRV_PER_ID = P.PER_ID
        LEFT JOIN DBO.DESCUENTOS_TB D
            ON I.PRD_DESC_ID = D.DESC_ID;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO


CREATE OR ALTER TRIGGER DBO.REGISTRAR_INVENTARIO_TR
ON DBO.INVENTARIOS_TB
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    BEGIN TRY
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
            'INVENTARIOS_TB',
            I.INV_ID,
            CASE
                WHEN @Origen IS NOT NULL
                    THEN 'Se usó ' + @Origen + ' y REGISTRAR_INVENTARIO_TR.'
                ELSE
                    'Se usó REGISTRAR_INVENTARIO_TR.'
            END,
            NULL,
            '[ Ubicación: ' + U.UBI_INV_Nombre +
            ' | Producto: ' + P.PRD_Descripcion +
            ' | Stock Mín: ' + CONVERT(VARCHAR(10), I.INV_StockMinimo) +
            ' | Stock Actual: ' + CONVERT(VARCHAR(10), I.INV_StockActual) +
            ' | Estado: ' + CASE WHEN I.INV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
        FROM INSERTED I
        INNER JOIN DBO.UBI_INVENTARIOS_TB U
            ON I.INV_UBI_INV_ID = U.UBI_INV_ID
        INNER JOIN DBO.PRODUCTOS_TB P
            ON I.INV_PRD_ID = P.PRD_ID;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO


CREATE OR ALTER TRIGGER DBO.MODIFICAR_INVENTARIO_TR
ON DBO.INVENTARIOS_TB
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT         = TRY_CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen     VARCHAR(75) = TRY_CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR(75));

    IF @Persona_ID IS NULL
        SET @Persona_ID = 1;

    BEGIN TRY
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
            'INVENTARIOS_TB',
            I.INV_ID,
            CASE
                WHEN @Origen IS NOT NULL
                    THEN 'Se usó ' + @Origen + ' y MODIFICAR_INVENTARIO_TR.'
                ELSE
                    'Se usó MODIFICAR_INVENTARIO_TR.'
            END,
            '[ Ubicación: ' + U.UBI_INV_Nombre +
            ' | Producto: ' + P.PRD_Descripcion +
            ' | Stock Mín: ' + CONVERT(VARCHAR(10), D.INV_StockMinimo) +
            ' | Stock Actual: ' + CONVERT(VARCHAR(10), D.INV_StockActual) +
            ' | Estado: ' + CASE WHEN D.INV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
            '[ Ubicación: ' + U.UBI_INV_Nombre +
            ' | Producto: ' + P.PRD_Descripcion +
            ' | Stock Mín: ' + CONVERT(VARCHAR(10), I.INV_StockMinimo) +
            ' | Stock Actual: ' + CONVERT(VARCHAR(10), I.INV_StockActual) +
            ' | Estado: ' + CASE WHEN I.INV_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
        FROM DELETED D
        INNER JOIN INSERTED I
            ON D.INV_ID = I.INV_ID
        INNER JOIN DBO.UBI_INVENTARIOS_TB U
            ON I.INV_UBI_INV_ID = U.UBI_INV_ID
        INNER JOIN DBO.PRODUCTOS_TB P
            ON I.INV_PRD_ID = P.PRD_ID;
    END TRY
    BEGIN CATCH
        -- Error en Auditoría no debe afectar el Trigger
    END CATCH
END;
GO