------------------------------
--- ****** DATABASE ****** ---
IF DB_ID('XSTORE') IS NULL
BEGIN
    CREATE DATABASE XSTORE;
END
GO

USE XSTORE;
GO


---- ****** PROCEDIMIENTOS ALMACENADOS ****** ----
CREATE PROCEDURE REGISTRAR_AUDITORIA_SP
	@Persona_ID INT,
	@Accion VARCHAR(25),
	@TablaAfectada VARCHAR(50),
	@FilaAfectada BIGINT,
	@Descripcion VARCHAR(250),
	@RESPUESTA BIT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	-- Normalización
	SET @Accion = UPPER(TRIM(@Accion));
	SET @TablaAfectada = TRIM(@TablaAfectada);
	SET @Descripcion = TRIM(@Descripcion); 

	-- Validación del ID persona
	IF NOT EXISTS(
		SELECT 1
		FROM DBO.PERSONAS_TB
		WHERE PER_ID = @Persona_ID
	)
	BEGIN
		SET @RESPUESTA = 0;
		RETURN;
	END

	IF @Accion NOT IN ('INSERT', 'UPDATE', 'DELETE')
	BEGIN
		SET @RESPUESTA = 0;
		RETURN;
	END

	BEGIN TRY
		
		BEGIN TRAN;

		INSERT INTO AUDITORIAS_TB(
			AUD_PER_ID, 
			AUD_Accion, 
			AUD_TablaAfectada, 
			AUD_FilaAfectada, 
			AUD_Descripcion
		) 
		VALUES
		(
			@Persona_ID,
			@Accion,
			@TablaAfectada,
			@FilaAfectada,
			@Descripcion
		)

		COMMIT;

		SET @RESPUESTA = 1;

	END TRY
	BEGIN CATCH
		ROLLBACK;
		SET @RESPUESTA = 0;
	END CATCH
END;


DECLARE @Resultado BIT;

EXEC REGISTRAR_AUDITORIA_SP
	@Persona_ID = 1,
	@Accion = 'INSERT',
	@TablaAfectada = 'PRODUCTOS_TB',
	@FilaAfectada = 50,
	@Descripcion = 'Registro de prueba exitoso',
	@RESPUESTA = @Resultado OUTPUT;

SELECT @Resultado AS '¿Fue exitoso?';
