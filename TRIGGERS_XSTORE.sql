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


CREATE OR ALTER TRIGGER DBO.REGISTRAR_ROL_TRG
ON DBO.ROLES_TB
FOR INSERT
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT = CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);
    DECLARE @Origen VARCHAR(75) = CAST(SESSION_CONTEXT(N'ORIGEN') AS VARCHAR);
    DECLARE @Rol_ID INT;
    DECLARE @DescripcionX VARCHAR(250);


    IF @Persona_ID IS NULL 
        SET @Persona_ID = 1; -- El sistema
    
    IF @Origen IS NOT NULL 
    BEGIN
        SET @DescripcionX = 'Se usó ' + @Origen + ' y REGISTRAR_ROL_TRG. (Rol registrado: ' + (SELECT ROL_Nombre From INSERTED) + ')';
    END
    ELSE 
    BEGIN
        SET @DescripcionX = 'Se usó REGISTRAR_ROL_TRG. (Rol registrado: ' + (SELECT ROL_Nombre From INSERTED) + ')';
    END

    SET @Rol_ID = (SELECT ROL_ID FROM INSERTED);
    
    EXEC REGISTRAR_AUDITORIA_SP
	    @Persona_ID = @Persona_ID,
	    @Accion = 'INSERT',
	    @TablaAfectada = 'ROLES_TB',
	    @FilaAfectada = @Rol_ID,
	    @Descripcion = @DescripcionX; 

        -- Cambiar formato de insertado debido a que solo guarda una auditoría
END;
GO

CREATE OR ALTER TRIGGER DBO.MODIFICAR_ROL_TRG
ON DBO.ROLES_TB
FOR UPDATE
AS
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT = CAST(SESSION_CONTEXT(N'PERSONA_ID') AS INT);

    IF @Persona_ID IS NULL 
        SET @Persona_ID = 1; -- El sistema

    DECLARE @ROL_ID INT;
    DECLARE @ROL_Nombre_Nuevo VARCHAR(50);
    DECLARE @ROL_Estado_Nuevo BIT;
    DECLARE @ROL_Nombre_Viejo VARCHAR(50) = (SELECT ROL_Nombre FROM DELETED);
    DECLARE @ROL_Estado_Viejo BIT = (SELECT ROL_Estado FROM DELETED);
    DECLARE @DESCRIPCIONX VARCHAR(250);

    SELECT 
        @ROL_ID = ROL_ID,
        @ROL_Nombre_Nuevo = ROL_Nombre,
        @ROL_Estado_Nuevo = ROL_Estado
    FROM INSERTED;

    SET @DescripcionX = 'Se usó MODIFICAR_ROL_SP y MODIFICAR_ROL_TRG. +' + 
                    '(Rol antes: [ Nombre: ' + (SELECT ROL_Nombre FROM DELETED) + ' | Estado: ' + (SELECT CAST(ROL_Estado AS VARCHAR) FROM DELETED) + ' ] ' + 
                    '-> Rol después: [ Nombre: ' + @ROL_Nombre_Nuevo + ' | Estado: ' + CAST(@ROL_Estado_Nuevo AS VARCHAR) + ' ])';

    EXEC REGISTRAR_AUDITORIA_SP
        @Persona_ID = @Persona_ID,
        @Accion = 'UPDATE',
        @TablaAfectada = 'ROLES_TB',
        @FilaAfectada = @Rol_ID,
        @Descripcion = @DescripcionX

END;
GO

