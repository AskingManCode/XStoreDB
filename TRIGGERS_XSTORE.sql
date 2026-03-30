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
 
    ROLLBACK TRANSACTION; 
 
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
        'UPDATE',
        'TIPOS_PRODUCTOS_TB',
        I.TIPO_PRD_ID,
        CASE
            WHEN @Origen IS NOT NULL
                THEN 'Se usó ' + @Origen + ' y MODIFICAR_TIPO_PRODUCTO_TR.'
            ELSE
                'Se usó MODIFICAR_TIPO_PRODUCTO_TR.'
        END,
        '[ Nombre: ' + I.TIPO_PRD_Nombre + ' | Estado: ' + CASE WHEN I.TIPO_PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]',
        '[ Nombre: ' + D.TIPO_PRD_Nombre + ' | Estado: ' + CASE WHEN D.TIPO_PRD_Estado = 1 THEN 'Activo' ELSE 'Inactivo' END + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.TIPO_PRD_ID = I.TIPO_PRD_ID;
END;
GO