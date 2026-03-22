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
CREATE OR ALTER TRIGGER DBO.TRG_BLOQUEAR_CAMBIOS_AUDITORIA
ON DBO.AUDITORIAS_TB
FOR UPDATE, DELETE 
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

-- No probado aún --
CREATE OR ALTER TRIGGER DBO.REGISTRAR_ROL_TRG
ON DBO.ROLES_TB
FOR INSERT
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT = CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Rol_ID INT = (SELECT ROL_ID FROM INSERTED);
    
    IF @Persona_ID IS NULL -- INSERT MANUAL
        SET @Persona_ID = 1; -- El sistema

    EXEC REGISTRAR_AUDITORIA_SP
	    @Persona_ID = @Persona_ID,
	    @Accion = 'INSERT',
	    @TablaAfectada = 'ROLES_TB',
	    @FilaAfectada = @Rol_ID,
	    @Descripcion = 'Se usó INSERT_ROL_SP y INSERT_ROL_TRG.'

END;
GO