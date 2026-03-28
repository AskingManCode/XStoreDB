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
CREATE OR ALTER TRIGGER DBO.BLOQUEAR_AUDITORIA_TRG
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


CREATE OR ALTER TRIGGER DBO.REGISTRAR_ROL_TRG
ON DBO.ROLES_TB
FOR INSERT
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT = CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen VARCHAR(75) = CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR);

    IF @Persona_ID IS NULL 
        SET @Persona_ID = 1; -- El sistema

    INSERT INTO AUDITORIAS_TB(
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
                THEN 'Se usó ' + @Origen + ' y REGISTRAR_ROL_TRG.'
            ELSE 
                'Se usó REGISTRAR_ROL_TRG.'
        END,
        NULL,
        '[ Nombre: ' + I.ROL_Nombre + ' | Accesos: ' + I.ROL_Accesos + ' | Estado: ' + CAST(I.ROL_ESTADO AS VARCHAR) + ' ]'
    FROM INSERTED I
END;
GO



CREATE OR ALTER TRIGGER DBO.MODIFICAR_ROL_TRG
ON DBO.ROLES_TB
FOR UPDATE
AS
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT = CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen VARCHAR(75) = CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR);

    IF @Persona_ID IS NULL 
        SET @Persona_ID = 1; -- El sistema

    INSERT INTO AUDITORIAS_TB(
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
                THEN 'Se usó ' + @Origen + ' y MODIFICAR_ROL_TRG.'
            ELSE 
                'Se usó MODIFICAR_ROL_TRG.'
        END,
        '[ Nombre: ' + D.ROL_Nombre + ' | Accesos: ' + D.ROL_Accesos + ' | Estado: ' + CAST(D.ROL_Estado AS VARCHAR) + ' ]',
        '[ Nombre: ' + I.ROL_Nombre + ' | Accesos: ' + I.ROL_Accesos + ' | Estado: ' + CAST(I.ROL_Estado AS VARCHAR) + ' ]'
    FROM DELETED D
    INNER JOIN INSERTED I
        ON D.ROL_ID = I.ROL_ID;
END;
GO