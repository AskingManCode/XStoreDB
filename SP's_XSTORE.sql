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
CREATE PROCEDURE RegistrarAuditoria_SP
	@Persona_ID INT,
	@Accion VARCHAR(25),
	@TablaAfectada VARCHAR(50),
	@RegistroID BIGINT,
	@Descripcion VARCHAR(250),
	@RESPUESTA BIT OUTPUT
AS
BEGIN -- Pruebita
	
	SET NOCOUNT ON;

	IF EXISTS(
		SELECT 1
		FROM PERSONAS_TB
		WHERE PER_ID = @Persona_ID
	)
		BEGIN

			INSERT INTO AUDITORIAS_TB(
				AUD_PER_ID, 
				AUD_Accion, 
				AUD_TablaAfectada, 
				AUD_RegistroID, 
				AUD_Descripcion
			) 
			VALUES
			(
				@Persona_ID,
				UPPER(TRIM(@Accion)),
				TRIM(@TablaAfectada),
				@RegistroID,
				TRIM(@Descripcion)
			)

			SET @RESPUESTA = 1;

		END
	ELSE
		BEGIN
			SET @RESPUESTA = 0;
		END
END; 


DECLARE @Resultado BIT;

EXEC RegistrarAuditoria_SP
	@Persona_ID = 1,
	@Accion = 'INSERT',
	@TablaAfectada = 'PRODUCTOS_TB',
	@RegistroID = 50,
	@Descripcion = 'Registro de prueba exitoso',
	@RESPUESTA = @Resultado OUTPUT;

SELECT @Resultado AS '¿Fue exitoso?';
