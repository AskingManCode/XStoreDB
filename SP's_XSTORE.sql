------------------------------
--- ****** DATABASE ****** ---
IF DB_ID('XSTORE') IS NULL
BEGIN
    CREATE DATABASE XSTORE;
END
GO

USE XSTORE;
GO

/* 
*	NOTA: Cada Procedimiento Almacenado es probado y validado varias veces
*	hasta que se identifique que está lo más funcional posible, cuálquier error, avisar
*/

---- ****** PROCEDIMIENTOS ALMACENADOS ****** ----
CREATE OR ALTER PROCEDURE DBO.REGISTRAR_AUDITORIA_SP -- No agregar al API
	@Persona_ID		INT, -- ID de la Persona Responsable
	@Accion			VARCHAR(25),
	@TablaAfectada	VARCHAR(75),
	@FilaAfectada	BIGINT,
	@Descripcion	VARCHAR(250),
	@Antes			VARCHAR(1000),
	@Despues		VARCHAR(1000)
AS
BEGIN
	
	SET NOCOUNT ON;

	BEGIN TRY
		
		-- Normalización
		SET @Accion			= UPPER(TRIM(ISNULL(@Accion, '')));
		SET @TablaAfectada	= UPPER(TRIM(ISNULL(@TablaAfectada, '')));
		SET @Descripcion	= TRIM(ISNULL(@Descripcion, ''));

        -- Validaciones
        IF NOT EXISTS (
            SELECT 1 
			FROM DBO.PERSONAS_TB 
			WHERE PER_ID = @Persona_ID
        )
        BEGIN
            RAISERROR('Persona_ID no existe para auditoría.', 16, 1);
            RETURN;
        END
		
		IF @Accion NOT IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
        BEGIN
            RAISERROR('Acción [%s] no válida para auditoría.', 16, 1, @Accion);
            RETURN;
        END

		IF LEN(@TablaAfectada) < 1
        BEGIN
            RAISERROR('Tabla no válida para auditoría.', 16, 1);
            RETURN;
        END

		-- SELECT siempre debe tener 0 filas afectadas
        IF @Accion = 'SELECT' AND @FilaAfectada != 0
        BEGIN
            RAISERROR('En SELECT, FilaAfectada debe ser 0.', 16, 1);
            RETURN;
        END

		-- Todo lo que no sea SELECT debe tener más de 0 filas afectadas
        IF @Accion != 'SELECT' AND @FilaAfectada <= 0
        BEGIN
            RAISERROR('ID de fila afectada no válido para auditoría.', 16, 1);
            RETURN;
        END

		-- Regla para SELECT: Ambos deben ser NULL
        IF @Accion = 'SELECT' AND (@Antes IS NOT NULL OR @Despues IS NOT NULL)
        BEGIN
            RAISERROR('En SELECT, los campos Antes/Después deben ser NULL.', 16, 1);
            RETURN;
        END

		-- Regla para INSERT: Antes NULL, Después con datos
        IF @Accion = 'INSERT' AND (@Antes IS NOT NULL OR @Despues IS NULL)
        BEGIN
            RAISERROR('En INSERT, "Antes" debe ser NULL y "Después" debe tener datos.', 16, 1);
            RETURN;
        END

		-- Regla para UPDATE: Ambos deben tener datos
        IF @Accion = 'UPDATE' AND (@Antes IS NULL OR @Despues IS NULL)
        BEGIN
            RAISERROR('En UPDATE, se requieren ambos estados (Antes y Después).', 16, 1);
            RETURN;
        END

		-- Regla para DELETE: Antes con datos, Después NULL
        IF @Accion = 'DELETE' AND (@Antes IS NULL OR @Despues IS NOT NULL)
        BEGIN
            RAISERROR('En DELETE, "Antes" debe tener datos y "Después" debe ser NULL.', 16, 1);
            RETURN;
        END

        IF LEN(@Descripcion) <= 10
        BEGIN
            RAISERROR('La descripción para la auditoría debe tener mínimo 11 caracteres.', 16, 10);
            RETURN;
        END

        INSERT INTO DBO.AUDITORIAS_TB (
            AUD_PER_ID, AUD_Accion, AUD_TablaAfectada, AUD_FilaAfectada,
            AUD_Descripcion, AUD_Antes, AUD_Despues
        )
        VALUES (
            @Persona_ID, @Accion, @TablaAfectada, @FilaAfectada,
            @Descripcion, @Antes, @Despues
        );

	END TRY
	BEGIN CATCH
		
		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_AUDITORIAS_SP
	@NombreUsuario	VARCHAR(75),    -- Responsable 
	@FechaFiltro	DATE			= NULL,
	@TablaFiltro	VARCHAR(75)		= NULL
AS
BEGIN

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; -- Evita que se bloqueen otras tablas
	
	DECLARE @Persona_ID INT;
    DECLARE @Descripcion VARCHAR(250);

	BEGIN TRY
		
		-- Validación de permisos y obtención de ID
		SELECT @Persona_ID = S.SESION_PER_ID
		FROM DBO.SESIONES_TB S
		INNER JOIN DBO.ROLES_TB R
			ON S.SESION_ROL_ID = R.ROL_ID
		WHERE S.SESION_NombreUsuario = @NombreUsuario
			AND S.SESION_Estado = 1
			AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        SELECT 
            P.PER_NombreCompleto AS [Responsable]
            , A.AUD_Accion AS [Acción]
            , A.AUD_TablaAfectada AS [Tabla Afectada]
            , A.AUD_FilaAfectada AS [Fila Afectada]
            , A.AUD_Descripcion AS [Descripción]
            , COALESCE(A.AUD_Antes, 'N/A') AS [Antes]
            , COALESCE(A.AUD_Despues, 'N/A') AS [Después]
            , A.AUD_FechaHora AS [Fecha y Hora]
        FROM DBO.AUDITORIAS_TB A
        INNER JOIN DBO.PERSONAS_TB P
            ON A.AUD_PER_ID = P.PER_ID
        WHERE (@FechaFiltro IS NULL OR CAST(A.AUD_FechaHora AS DATE) = @FechaFiltro)
            AND (@TablaFiltro IS NULL OR A.AUD_TablaAfectada = UPPER(TRIM(@TablaFiltro)))
        ORDER BY A.AUD_FechaHora DESC; -- Fechas recientes primero

        SET @Descripcion = 'Se usó CONSULTAR_AUDITORIAS_SP' + 
            CASE 
                WHEN ISNULL(@TablaFiltro, '') != '' 
                    THEN ' con filtro [' + @TablaFiltro + '].'
                ELSE 
                    ' sin filtro específico (Todos).'
            END;

		BEGIN TRY
			EXEC DBO.REGISTRAR_AUDITORIA_SP
				@Persona_ID		= @Persona_ID,
				@Accion			= 'SELECT',
				@TablaAfectada	= 'AUDITORIAS_TB',
				@FilaAfectada	= 0,
				@Descripcion	= @Descripcion,
				@Antes			= NULL,
				@Despues		= NULL
		END TRY
		BEGIN CATCH
			-- Falla en auditoría no debe interrumpir la consulta
		END CATCH

	END TRY
	BEGIN CATCH
		
		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH

	SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_ROLES_SP
	@NombreUsuario	VARCHAR(75) -- Responsable
AS
BEGIN

	SET NOCOUNT ON;

	DECLARE @Persona_ID INT;

	BEGIN TRY

        -- Validaciónes
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

		SELECT 
			ROL_Nombre AS [Rol]
			, ROL_Accesos AS [Accesos]
			, CASE 
                WHEN ROL_Estado = 1
                    THEN 'Activo'
                ELSE
                    'Inactivo'
            END AS [Estado Rol]
		FROM DBO.ROLES_TB;

		BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'ROLES_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó CONSULTAR_ROLES_SP.',
                @Antes          = NULL,
                @Despues        = NULL;
			END TRY
		BEGIN CATCH
			-- Falla en auditoría no debe interrumpir la consulta
		END CATCH

	END TRY
	BEGIN CATCH

		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_ROL_SP
	@NombreUsuario	VARCHAR(75), -- Responsable
	@Nombre			VARCHAR(50),
	@Accesos		VARCHAR(500) -- Pantallas a las que puede acceder el rol
AS
BEGIN
	
	SET XACT_ABORT ON;
	SET NOCOUNT ON;

	DECLARE @Persona_ID INT;
	SET @Nombre	 = TRIM(ISNULL(@Nombre, ''))
	SET @Accesos = TRIM(ISNULL(@Accesos, ''))

	BEGIN TRY

		BEGIN TRANSACTION;

		-- Validación de permisos y obtención de ID
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        IF LEN(@Nombre) <= 0
        BEGIN
            RAISERROR('Error: El nombre del rol no es válido.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 
			FROM DBO.ROLES_TB 
			WHERE ROL_Nombre = @Nombre
        )
        BEGIN
            RAISERROR('Error: El rol [%s] ya se encuentra registrado.', 16, 1, @Nombre);
            RETURN;
        END

        IF LEN(@Accesos) <= 0
        BEGIN
            RAISERROR('Error: Los accesos no son válidos.', 16, 1);
            RETURN;
        END

		-- Guarda Persona ID
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_ROL_SP';

		INSERT INTO DBO.ROLES_TB (ROL_Nombre, ROL_Accesos)
		VALUES (@Nombre, @Accesos);

        COMMIT;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

	END TRY
	BEGIN CATCH
		
		IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_ROL_SP
    @NombreUsuario  VARCHAR(75),    -- Responsable
    @Nombre         VARCHAR(50),    -- Nombre actual del rol a modificar
    @NuevoNombre    VARCHAR(50)     = NULL,
    @NuevosAccesos  VARCHAR(500)    = NULL,
    @NuevoEstado    BIT             = NULL
AS
BEGIN
	
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID     INT;
    DECLARE @Rol_ID         INT;
    DECLARE @EsRolCritico   BIT = 0;
 
    SET @Nombre        = TRIM(ISNULL(@Nombre, ''));
    SET @NuevoNombre   = TRIM(ISNULL(@NuevoNombre, ''));
    SET @NuevosAccesos = TRIM(ISNULL(@NuevosAccesos, ''));

	BEGIN TRY 
		
		BEGIN TRANSACTION;

		-- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R 
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

		-- Obtener datos del rol a modificar
        SELECT 
            @Rol_ID = ROL_ID,
            @EsRolCritico = CASE WHEN ROL_Nombre = 'Administrador' THEN 1 ELSE 0 END
        FROM DBO.ROLES_TB
        WHERE ROL_Nombre = @Nombre;

        IF @Rol_ID IS NULL
        BEGIN
            RAISERROR('Error: El rol [%s] no existe.', 16, 1, @Nombre);
            RETURN;
        END
		
		-- Protección de rol de administrador
        IF @EsRolCritico = 1 AND (@NuevoEstado = 0 OR LEN(@NuevoNombre) > 0)
        BEGIN
            RAISERROR('No se permite renombrar o desactivar el rol Administrador por seguridad.', 16, 1);
            RETURN;
        END

        IF LEN(@NuevoNombre) = 0
            AND LEN(@NuevosAccesos) = 0
            AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para el rol [%s].', 16, 1, @Nombre);
            RETURN;
        END

        -- Validar nuevo nombre
        IF LEN(@NuevoNombre) > 0
        BEGIN
            IF EXISTS (
                SELECT 1 
                FROM DBO.ROLES_TB 
                WHERE ROL_Nombre = @NuevoNombre 
                  AND ROL_ID != @Rol_ID
            )
            BEGIN
                RAISERROR('Error: Ya existe un rol con el nombre [%s].', 16, 1, @NuevoNombre);
                RETURN;
            END
        END

        -- Validación para desactivar rol en uso
        /*IF @NuevoEstado = 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.SESIONES_TB
                WHERE SESION_ROL_ID = @Rol_ID 
					AND SESION_Estado = 1
            )
            BEGIN
                RAISERROR('No se puede desactivar el rol porque hay sesiones activas que lo usan.', 16, 1);
            END
        END */
        		
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_ROL_SP';

        UPDATE DBO.ROLES_TB
        SET 
            ROL_Nombre  = ISNULL(NULLIF(@NuevoNombre,   ''), ROL_Nombre),
            ROL_Accesos = ISNULL(NULLIF(@NuevosAccesos, ''), ROL_Accesos),
            ROL_Estado  = ISNULL(@NuevoEstado, ROL_Estado)
        WHERE ROL_ID = @Rol_ID;

		COMMIT;

		EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
		EXEC SP_SET_SESSION_CONTEXT 'ORIGEN' , NULL;

	END TRY
	BEGIN CATCH
		
		IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_TIPOS_PRODUCTOS_SP
    @NombreUsuario  VARCHAR(75) = NULL   -- Responsable
AS 
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;

    BEGIN TRY
        
        if @NombreUsuario IS NULL
        BEGIN
            SET @Persona_ID = 1; -- Fallback al Sistema
        END
        ELSE
        BEGIN
            -- Validaciones
            SELECT @Persona_ID = S.SESION_PER_ID
            FROM DBO.SESIONES_TB S
            INNER JOIN DBO.ROLES_TB R
                ON S.SESION_ROL_ID = R.ROL_ID
            WHERE S.SESION_NombreUsuario = @NombreUsuario
                AND S.SESION_Estado = 1;

            IF @Persona_ID IS NULL
            BEGIN
                RAISERROR('Error: El usuario [%s] no es válido', 16, 1, @NombreUsuario);
                RETURN;
            END;
        END;

        SELECT 
            TIPO_PRD_Nombre AS [Tipos Productos]
            , CASE
                WHEN TIPO_PRD_Estado = 1
                    THEN 'Activo'
                ELSE 
                    'Inactivo'
            END AS [Estado]
        FROM DBO.TIPOS_PRODUCTOS_TB;

        -- Auditoría
        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'TIPOS_PRODUCTOS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó CONSULTAR_TIPOS_PRODUCTOS_SP.',
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH
        
		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

    END CATCH
END
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_TIPO_PRODUCTO_SP
    @NombreUsuario	VARCHAR(75), -- Responsable
	@Nombre			VARCHAR(50)
AS
BEGIN
    
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

	DECLARE @Persona_ID INT;
	SET @Nombre	= TRIM(ISNULL(@Nombre, ''))

    BEGIN TRY
        
        BEGIN TRANSACTION;

        -- Validación de permisos y obtener ID
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN
        END;

        IF LEN(@Nombre) <= 0
        BEGIN
            RAISERROR('Error: El nombre del tipo de producto no es válido.', 16, 1);
            RETURN
        END;

        IF EXISTS (
            SELECT 1 
			FROM DBO.TIPOS_PRODUCTOS_TB 
			WHERE TIPO_PRD_Nombre = @Nombre
        )
        BEGIN
            RAISERROR('Error: El tipo de producto [%s] ya se encuentra registrado.', 16, 1, @Nombre);
            RETURN;
        END

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_TIPO_PRODUCTO_SP';

        INSERT INTO DBO.TIPOS_PRODUCTOS_TB (TIPO_PRD_Nombre)
        VALUES (@Nombre);

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH
        
		IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_TIPO_PRODUCTO_SP
    @NombreUsuario  VARCHAR(75),    -- Responsable
    @Nombre         VARCHAR(50),    -- Nombre actual del tipo de producto a modificar
    @NuevoNombre    VARCHAR(50)     = NULL,
    @NuevoEstado    BIT             = NULL
AS 
BEGIN
    
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID   INT;
    DECLARE @Tipo_PRD_ID  INT;

    SET @Nombre       = TRIM(ISNULL(@Nombre, ''));
    SET @NuevoNombre  = TRIM(ISNULL(@NuevoNombre, ''));

    BEGIN TRY
        
        BEGIN TRANSACTION

        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R 
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END

        -- Obtener los datos del tipo de producto a modificar
        SELECT @Tipo_PRD_ID = TIPO_PRD_ID
        FROM DBO.TIPOS_PRODUCTOS_TB
        WHERE TIPO_PRD_Nombre = @Nombre;

        IF @Tipo_PRD_ID IS NULL
        BEGIN
            RAISERROR('Error: El tipo de producto [%s] no existe.', 16, 1, @Nombre);
            RETURN;
        END;

        IF LEN(@NuevoNombre) = 0
            AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para el tipo de producto [%s].', 16, 1, @Nombre);
            RETURN;
        END

        -- Validación de nuevo nombre
        IF LEN(@NuevoNombre) > 0
        BEGIN
            IF EXISTS(
                SELECT 1
                FROM DBO.TIPOS_PRODUCTOS_TB
                WHERE TIPO_PRD_Nombre = @NuevoNombre
                    AND TIPO_PRD_ID != @Tipo_PRD_ID
            )
            BEGIN
                RAISERROR('Error: Ya existe un tipo de producto con el nombre [%s].', 16, 1, @NuevoNombre);
                RETURN;
            END
        END;

        -- Validación para desactivar un tipo de poroducto en uso
        /*IF @NuevoEstado = 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.PRODUCTOS_TB
                WHERE PRD_TIPO_PRD_ID = @Tipo_PRD_ID 
					AND PRD_Estado = 1
            )
            BEGIN
                RAISERROR('No se puede desactivar el tipo de producto porque hay productos activos que lo usan.', 16, 1);
            END
        END */

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_TIPO_PRODUCTO_SP';

        UPDATE DBO.TIPOS_PRODUCTOS_TB
        SET
            TIPO_PRD_Nombre = ISNULL(NULLIF(@NuevoNombre, ''), TIPO_PRD_Nombre),
            TIPO_PRD_Estado = ISNULL(@NuevoEstado, TIPO_PRD_Estado)
        WHERE TIPO_PRD_ID = @Tipo_PRD_ID;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH
        
		IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_MARCAS_PRODUCTOS_SP
    @NombreUsuario VARCHAR(75) = NULL -- Responsable
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT;
 
    BEGIN TRY
 
        IF @NombreUsuario IS NULL
        BEGIN 
            SET @Persona_ID = 1; -- Fallback al sistema
        END
        ELSE
        BEGIN
            -- Validación de usuario activo
            SELECT @Persona_ID = S.SESION_PER_ID
            FROM DBO.SESIONES_TB S
            INNER JOIN DBO.ROLES_TB R
                ON S.SESION_ROL_ID = R.ROL_ID
            WHERE S.SESION_NombreUsuario = @NombreUsuario
                AND S.SESION_Estado = 1;
 
            IF @Persona_ID IS NULL
            BEGIN
                RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
                RETURN;
            END;
        END;
 
        SELECT
            MARC_PRD_Nombre AS [Marca]
            , CASE
                WHEN MARC_PRD_Estado = 1
                    THEN 'Activo'
                ELSE
                    'Inactivo'
            END AS [Estado]
        FROM DBO.MARCAS_PRODUCTOS_TB;
 
        -- Auditoría
        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'MARCAS_PRODUCTOS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó CONSULTAR_MARCAS_PRODUCTOS_SP.',
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH
 
    END TRY
    BEGIN CATCH
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_MARCA_PRODUCTO_SP
    @NombreUsuario  VARCHAR(75),  -- Responsable
    @Nombre         VARCHAR(75)   -- Nombre de la nueva marca
AS
BEGIN
 
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT;
    SET @Nombre = TRIM(ISNULL(@Nombre, ''));
 
    BEGIN TRY
 
        BEGIN TRANSACTION;
 
        -- Validación de permisos y obtención de ID
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;
 
        IF LEN(@Nombre) <= 0
        BEGIN
            RAISERROR('Error: El nombre de la marca no es válido.', 16, 1);
            RETURN;
        END;
 
        IF EXISTS (
            SELECT 1
            FROM DBO.MARCAS_PRODUCTOS_TB
            WHERE MARC_PRD_Nombre = @Nombre
        )
        BEGIN
            RAISERROR('Error: La marca [%s] ya se encuentra registrada.', 16, 1, @Nombre);
            RETURN;
        END;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_MARCA_PRODUCTO_SP';
 
        INSERT INTO DBO.MARCAS_PRODUCTOS_TB (MARC_PRD_Nombre)
        VALUES (@Nombre);
 
        COMMIT;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
    END TRY
    BEGIN CATCH
 
        IF @@TRANCOUNT > 0 ROLLBACK;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_MARCA_PRODUCTO_SP
    @NombreUsuario  VARCHAR(75),            -- Responsable
    @Nombre         VARCHAR(75),            -- Nombre actual de la marca a modificar
    @NuevoNombre    VARCHAR(75)  = NULL,
    @NuevoEstado    BIT          = NULL
AS
BEGIN
 
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID   INT;
    DECLARE @Marc_PRD_ID  INT;
 
    SET @Nombre      = TRIM(ISNULL(@Nombre, ''));
    SET @NuevoNombre = TRIM(ISNULL(@NuevoNombre, ''));
 
    BEGIN TRY
 
        BEGIN TRANSACTION;
 
        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;
 
        -- Obtener ID de la marca a modificar
        SELECT @Marc_PRD_ID = MARC_PRD_ID
        FROM DBO.MARCAS_PRODUCTOS_TB
        WHERE MARC_PRD_Nombre = @Nombre;
 
        IF @Marc_PRD_ID IS NULL
        BEGIN
            RAISERROR('Error: La marca [%s] no existe.', 16, 1, @Nombre);
            RETURN;
        END;
 
        -- Detectar si no se pasó ningún cambio
        IF LEN(@NuevoNombre) = 0
            AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para la marca [%s].', 16, 1, @Nombre);
            RETURN;
        END;
 
        -- Validar que el nuevo nombre no esté en uso por otra marca
        IF LEN(@NuevoNombre) > 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.MARCAS_PRODUCTOS_TB
                WHERE MARC_PRD_Nombre = @NuevoNombre
                    AND MARC_PRD_ID != @Marc_PRD_ID
            )
            BEGIN
                RAISERROR('Error: Ya existe una marca con el nombre [%s].', 16, 1, @NuevoNombre);
                RETURN;
            END;
        END;
 
        -- Validación para desactivar marca en uso
        /*IF @NuevoEstado = 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.PRODUCTOS_TB
                WHERE PRD_MARC_PRD_ID = @Marc_PRD_ID
                    AND PRD_Estado = 1
            )
            BEGIN
                RAISERROR('No se puede desactivar la marca porque hay productos activos que la usan.', 16, 1);
                RETURN;
            END;
        END;*/
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_MARCA_PRODUCTO_SP';
 
        UPDATE DBO.MARCAS_PRODUCTOS_TB
        SET
            MARC_PRD_Nombre = ISNULL(NULLIF(@NuevoNombre, ''), MARC_PRD_Nombre),
            MARC_PRD_Estado = ISNULL(@NuevoEstado, MARC_PRD_Estado)
        WHERE MARC_PRD_ID = @Marc_PRD_ID;
 
        COMMIT;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
    END TRY
    BEGIN CATCH
 
        IF @@TRANCOUNT > 0 ROLLBACK;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_UBICACIONES_SP
    @NombreUsuario  VARCHAR(75)     -- Responsable
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT;
 
    BEGIN TRY
 
        -- Validación de usuario activo
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;
 
        SELECT
            UBI_INV_Nombre AS [Ubicación]
            , CASE
                WHEN UBI_INV_Estado = 1
                    THEN 'Activo'
                ELSE
                    'Inactivo'
            END AS [Estado]
        FROM DBO.UBI_INVENTARIOS_TB;
 
        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'UBI_INVENTARIOS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó CONSULTAR_UBICACIONES_SP.',
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH
 
    END TRY
    BEGIN CATCH
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_UBICACION_SP
    @NombreUsuario  VARCHAR(75),    -- Responsable
    @Nombre         VARCHAR(75)     -- Nombre de la nueva ubicación
AS
BEGIN
 
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT;
    SET @Nombre = TRIM(ISNULL(@Nombre, ''));
 
    BEGIN TRY
 
        BEGIN TRANSACTION;
 
        -- Validación de permisos y obtención de ID
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;
 
        IF LEN(@Nombre) <= 0
        BEGIN
            RAISERROR('Error: El nombre de la ubicación no es válido.', 16, 1);
            RETURN;
        END;
 
        IF EXISTS (
            SELECT 1
            FROM DBO.UBI_INVENTARIOS_TB
            WHERE UBI_INV_Nombre = @Nombre
        )
        BEGIN
            RAISERROR('Error: La ubicación [%s] ya se encuentra registrada.', 16, 1, @Nombre);
            RETURN;
        END;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_UBICACION_SP';
 
        INSERT INTO DBO.UBI_INVENTARIOS_TB (UBI_INV_Nombre)
        VALUES (@Nombre);
 
        COMMIT;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
    END TRY
    BEGIN CATCH
 
        IF @@TRANCOUNT > 0 ROLLBACK;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_UBICACION_SP
    @NombreUsuario  VARCHAR(75),            -- Responsable
    @Nombre         VARCHAR(75),            -- Nombre actual de la ubicación a modificar
    @NuevoNombre    VARCHAR(75)  = NULL,
    @NuevoEstado    BIT          = NULL
AS
BEGIN
 
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT;
    DECLARE @UBI_INV_ID INT;
 
    SET @Nombre      = TRIM(ISNULL(@Nombre, ''));
    SET @NuevoNombre = TRIM(ISNULL(@NuevoNombre, ''));
 
    BEGIN TRY
 
        BEGIN TRANSACTION;
 
        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;
 
        -- Obtener ID de la ubicación a modificar
        SELECT @UBI_INV_ID = UBI_INV_ID
        FROM DBO.UBI_INVENTARIOS_TB
        WHERE UBI_INV_Nombre = @Nombre;
 
        IF @UBI_INV_ID IS NULL
        BEGIN
            RAISERROR('Error: La ubicación [%s] no existe.', 16, 1, @Nombre);
            RETURN;
        END;
 
        -- Detectar si no se pasó ningún cambio
        IF LEN(@NuevoNombre) = 0
            AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para la ubicación [%s].', 16, 1, @Nombre);
            RETURN;
        END;
 
        -- Validar que el nuevo nombre no esté en uso por otra ubicación
        IF LEN(@NuevoNombre) > 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.UBI_INVENTARIOS_TB
                WHERE UBI_INV_Nombre = @NuevoNombre
                    AND UBI_INV_ID != @UBI_INV_ID
            )
            BEGIN
                RAISERROR('Error: Ya existe una ubicación con el nombre [%s].', 16, 1, @NuevoNombre);
                RETURN;
            END;
        END;
 
        -- Validación para desactivar ubicación en uso
        /*IF @NuevoEstado = 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.INVENTARIOS_TB
                WHERE INV_UBI_INV_ID = @UBI_INV_ID
                    AND INV_Estado = 1
            )
            BEGIN
                RAISERROR('No se puede desactivar la ubicación porque tiene inventario activo asignado.', 16, 1);
                RETURN;
            END;
        END;*/
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_UBICACION_SP';
 
        UPDATE DBO.UBI_INVENTARIOS_TB
        SET
            UBI_INV_Nombre = ISNULL(NULLIF(@NuevoNombre, ''), UBI_INV_Nombre),
            UBI_INV_Estado = ISNULL(@NuevoEstado, UBI_INV_Estado)
        WHERE UBI_INV_ID = @UBI_INV_ID;
 
        COMMIT;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
    END TRY
    BEGIN CATCH
 
        IF @@TRANCOUNT > 0 ROLLBACK;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_CAT_DESCUENTOS_SP
    @NombreUsuario  VARCHAR(75)     -- Responsable
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;

    BEGIN TRY

        -- Validación de usuario activo
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        SELECT
            CAT_DESC_Nombre AS [Categoría Descuento]
            , CASE
                WHEN CAT_DESC_Estado = 1
                    THEN 'Activo'
                ELSE
                    'Inactivo'
            END AS [Estado]
        FROM DBO.CAT_DESCUENTOS_TB;

        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'CAT_DESCUENTOS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó CONSULTAR_CAT_DESCUENTOS_SP.',
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_CAT_DESCUENTO_SP
    @NombreUsuario  VARCHAR(75),    -- Responsable
    @Nombre         VARCHAR(75)     -- Nombre de la nueva categoría
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;
    SET @Nombre = TRIM(ISNULL(@Nombre, ''));

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Validación de permisos y obtención de ID
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        IF LEN(@Nombre) <= 0
        BEGIN
            RAISERROR('Error: El nombre de la categoría no es válido.', 16, 1);
            RETURN;
        END;

        IF EXISTS (
            SELECT 1
            FROM DBO.CAT_DESCUENTOS_TB
            WHERE CAT_DESC_Nombre = @Nombre
        )
        BEGIN
            RAISERROR('Error: La categoría [%s] ya se encuentra registrada.', 16, 1, @Nombre);
            RETURN;
        END;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_CAT_DESCUENTO_SP';

        INSERT INTO DBO.CAT_DESCUENTOS_TB (CAT_DESC_Nombre)
        VALUES (@Nombre);

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_CAT_DESCUENTO_SP
    @NombreUsuario  VARCHAR(75),            -- Responsable
    @Nombre         VARCHAR(75),            -- Nombre actual de la categoría a modificar
    @NuevoNombre    VARCHAR(75)  = NULL,
    @NuevoEstado    BIT          = NULL
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID   INT;
    DECLARE @CAT_DESC_ID  INT;

    SET @Nombre      = TRIM(ISNULL(@Nombre,      ''));
    SET @NuevoNombre = TRIM(ISNULL(@NuevoNombre, ''));

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Obtener ID de la categoría a modificar
        SELECT @CAT_DESC_ID = CAT_DESC_ID
        FROM DBO.CAT_DESCUENTOS_TB
        WHERE CAT_DESC_Nombre = @Nombre;

        IF @CAT_DESC_ID IS NULL
        BEGIN
            RAISERROR('Error: La categoría [%s] no existe.', 16, 1, @Nombre);
            RETURN;
        END;

        -- Detectar si no se pasó ningún cambio
        IF LEN(@NuevoNombre) = 0
            AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para la categoría [%s].', 16, 1, @Nombre);
            RETURN;
        END;

        -- Validar que el nuevo nombre no esté en uso por otra categoría
        IF LEN(@NuevoNombre) > 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.CAT_DESCUENTOS_TB
                WHERE CAT_DESC_Nombre = @NuevoNombre
                    AND CAT_DESC_ID != @CAT_DESC_ID
            )
            BEGIN
                RAISERROR('Error: Ya existe una categoría con el nombre [%s].', 16, 1, @NuevoNombre);
                RETURN;
            END;
        END;

        -- Validación para desactivar categoría en uso
        /*IF @NuevoEstado = 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.DESCUENTOS_TB
                WHERE DESC_CAT_DESC_ID = @CAT_DESC_ID
                    AND DESC_Estado = 1
            )
            BEGIN
                RAISERROR('No se puede desactivar la categoría porque hay descuentos activos que la usan.', 16, 1);
                RETURN;
            END;
        END;*/

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_CAT_DESCUENTO_SP';

        UPDATE DBO.CAT_DESCUENTOS_TB
        SET
            CAT_DESC_Nombre = ISNULL(NULLIF(@NuevoNombre, ''), CAT_DESC_Nombre),
            CAT_DESC_Estado = ISNULL(@NuevoEstado, CAT_DESC_Estado)
        WHERE CAT_DESC_ID = @CAT_DESC_ID;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_TIPOS_PERSONAS_SP
    @NombreUsuario VARCHAR(75)
AS
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;

    BEGIN TRY

        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
          AND S.SESION_Estado = 1;

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        SELECT
            TP.TIPO_PER_Nombre AS [Tipo Persona],
            TP.TIPO_PER_DescuentoPct AS [Descuento %],
            TP.TIPO_PER_MontoMeta AS [Monto Meta],
            CASE
                WHEN TP.TIPO_PER_Estado = 1 
                    THEN 'Activo'
                ELSE 
                    'Inactivo'
            END AS [Estado]
        FROM DBO.TIPOS_PERSONAS_TB TP
        WHERE TP.TIPO_PER_Nombre != 'SISTEMA'
        ORDER BY TP.TIPO_PER_ID;

        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'TIPOS_PERSONAS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó CONSULTAR_TIPOS_PERSONAS_SP.',
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH;

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_TIPO_PERSONA_SP
    @NombreUsuario  VARCHAR(75),    -- Responsable
    @Nombre         VARCHAR(50),
    @DescuentoPct   DECIMAL(5,2),
    @MontoMeta      DECIMAL(10,2)
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;
    SET @Nombre = TRIM(ISNULL(@Nombre, ''));

    BEGIN TRY

        BEGIN TRANSACTION;

        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
          AND S.SESION_Estado = 1
          AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        IF LEN(@Nombre) <= 0
        BEGIN
            RAISERROR('Error: El nombre del tipo de persona no es válido.', 16, 1);
            RETURN;
        END;

        IF EXISTS (
            SELECT 1
            FROM DBO.TIPOS_PERSONAS_TB
            WHERE TIPO_PER_Nombre = @Nombre
        )
        BEGIN
            RAISERROR('Error: El tipo de persona [%s] ya está registrado.', 16, 1, @Nombre);
            RETURN;
        END;

        IF @DescuentoPct < 0 OR @DescuentoPct > 100
        BEGIN
            RAISERROR('Error: El descuento debe estar entre 0 y 100.', 16, 1);
            RETURN;
        END;

        IF @MontoMeta < 0
        BEGIN
            RAISERROR('Error: El monto meta no puede ser negativo.', 16, 1);
            RETURN;
        END;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_TIPO_PERSONA_SP';

        INSERT INTO DBO.TIPOS_PERSONAS_TB (TIPO_PER_Nombre, TIPO_PER_DescuentoPct, TIPO_PER_MontoMeta)
        VALUES (@Nombre, @DescuentoPct, @MontoMeta);

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_TIPO_PERSONA_SP
    @NombreUsuario      VARCHAR(75),
    @Nombre             VARCHAR(50),
    @NuevoNombre        VARCHAR(50)     = NULL,
    @NuevoDescuentoPct  DECIMAL(5,2)    = NULL,
    @NuevoMontoMeta     DECIMAL(10,2)   = NULL,
    @NuevoEstado        BIT             = NULL
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID     INT;
    DECLARE @Tipo_Per_ID    INT;
    DECLARE @EsCritico      BIT = 0;

    SET @NuevoNombre = TRIM(ISNULL(@NuevoNombre, ''));

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Obtener los datos del tipo de persona a modificar
        SELECT
            @Tipo_Per_ID = TIPO_PER_ID,
            @EsCritico = CASE WHEN TIPO_PER_Nombre = 'SISTEMA' THEN 1 ELSE 0 END
        FROM DBO.TIPOS_PERSONAS_TB
        WHERE TIPO_PER_Nombre = @Nombre;

        IF @Tipo_Per_ID IS NULL
        BEGIN
            RAISERROR('Error: El tipo de persona [%s] no existe.', 16, 1, @Nombre);
            RETURN;
        END;

        IF @EsCritico = 1 AND (LEN(@NuevoNombre) > 0 OR @NuevoEstado = 0)
        BEGIN
            RAISERROR('No se permite renombrar o desactivar el tipo de persona SISTEMA.', 16, 1);
            RETURN;
        END;

        IF LEN(@NuevoNombre) = 0
           AND @NuevoDescuentoPct IS NULL
           AND @NuevoMontoMeta IS NULL
           AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para el tipo de persona.', 16, 1);
            RETURN;
        END;

        IF LEN(@NuevoNombre) > 0
           AND EXISTS (
                SELECT 1
                FROM DBO.TIPOS_PERSONAS_TB
                WHERE TIPO_PER_Nombre = @NuevoNombre
                  AND TIPO_PER_ID != @Tipo_Per_ID
           )
        BEGIN
            RAISERROR('Error: Ya existe un tipo de persona con nombre [%s].', 16, 1, @NuevoNombre);
            RETURN;
        END;

        IF @NuevoDescuentoPct IS NOT NULL
           AND (@NuevoDescuentoPct < 0 OR @NuevoDescuentoPct > 100)
        BEGIN
            RAISERROR('Error: El descuento debe estar entre 0 y 100.', 16, 1);
            RETURN;
        END;

        IF @NuevoMontoMeta IS NOT NULL
           AND @NuevoMontoMeta < 0
        BEGIN
            RAISERROR('Error: El monto meta no puede ser negativo.', 16, 1);
            RETURN;
        END;

        -- Validación para desactivar un tipo de persona en uso
        /*IF @NuevoEstado = 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.PERSONAS_TB
                WHERE PER_TIPO_PER_ID = @Tipo_Per_ID 
                    AND PER_Estado = 1
            )
            BEGIN
                RAISERROR('No se puede desactivar el tipo de persona porque hay personas activas que lo usan.', 16, 1);
                RETURN;
            END
        END */

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_TIPO_PERSONA_SP';

        UPDATE DBO.TIPOS_PERSONAS_TB
        SET
            TIPO_PER_Nombre         = ISNULL(NULLIF(@NuevoNombre, ''), TIPO_PER_Nombre),
            TIPO_PER_DescuentoPct   = ISNULL(@NuevoDescuentoPct, TIPO_PER_DescuentoPct),
            TIPO_PER_MontoMeta      = ISNULL(@NuevoMontoMeta, TIPO_PER_MontoMeta),
            TIPO_PER_Estado         = ISNULL(@NuevoEstado, TIPO_PER_Estado)
        WHERE TIPO_PER_ID = @Tipo_Per_ID;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN'    , NULL;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN'    , NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_PERSONAS_SP
    @NombreUsuario      VARCHAR(75),
    @RolFiltro          VARCHAR(20)   = NULL,  -- Administradores, Vendedores, Clientes, Proveedores, NULL = Todos
    @TipoPersonaFiltro  VARCHAR(50)   = NULL,  -- Nombre exacto del tipo de persona, NULL = Todos
    @Busqueda           VARCHAR(100)  = NULL   -- Búsqueda parcial: Identificación, Nombre, Correo, Teléfono, NombreUsuario
AS 
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID     INT;
    DECLARE @BusquedaLike   VARCHAR(102);
    DECLARE @Descripcion    VARCHAR(250);

    SET @RolFiltro = UPPER(TRIM(ISNULL(@RolFiltro, '')));

    BEGIN TRY

        -- Validación de usuario activo
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Preparación del parámetro de búsqueda
        IF @Busqueda IS NOT NULL
            SET @BusquedaLike = '%' + TRIM(@Busqueda) + '%';

        -- Filtro de rol inválido
        IF @RolFiltro NOT IN ('ADMINISTRADORES', 'VENDEDORES', 'CLIENTES', 'PROVEEDORES', '')
        BEGIN
            RAISERROR('Error: Filtro [%s] no válido. Use: Administradores, Vendedores, Clientes, Proveedores o deje vacío para mostrar a todos.', 16, 1, @RolFiltro);
            RETURN;
        END;

        -- Personas con sesión (Administradores, Vendedores, Clientes)
        SELECT 
            P.PER_Identificacion AS [Identificación]
            , P.PER_NombreCompleto AS [Nombre Completo]
            , P.PER_Telefono AS [Teléfono]
            , P.PER_Correo AS [Correo]
            , P.PER_Direccion AS [Dirección]
            , TP.TIPO_PER_Nombre AS [Tipo Persona]
            , CONVERT(VARCHAR(5), TP.TIPO_PER_DescuentoPct) + '%' AS [Descuento %]
            , R.ROL_Nombre AS [Rol]
            , S.SESION_NombreUsuario AS [Nombre Usuario]
            , CONVERT(VARCHAR(10), P.PER_FechaRegistro, 120) AS [Fecha Registro]
            , CASE 
                WHEN P.PER_Estado = 1
                    THEN 'Activo'
                ELSE 
                    'Inactivo'
            END AS [Estado]
        FROM DBO.PERSONAS_TB P
        INNER JOIN DBO.TIPOS_PERSONAS_TB TP
            ON P.PER_TIPO_PER_ID = TP.TIPO_PER_ID
        INNER JOIN DBO.SESIONES_TB S
            ON P.PER_ID = S.SESION_PER_ID
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE P.PER_ID != 1  -- Reservado para SISTEMA
            AND (   -- Filtro por rol
                @RolFiltro = ''
                OR (@RolFiltro = 'ADMINISTRADORES' AND R.ROL_Nombre = 'Administrador')
                OR (@RolFiltro = 'VENDEDORES' AND R.ROL_Nombre = 'Vendedor')
                OR (@RolFiltro = 'CLIENTES' AND R.ROL_Nombre = 'Cliente')
            )
            AND (   -- Filtro por tipo de persona
                @TipoPersonaFiltro IS NULL
                OR TP.TIPO_PER_Nombre = @TipoPersonaFiltro
            )
            AND (   -- Filtro de búsqueda
                @Busqueda IS NULL
                OR P.PER_Identificacion LIKE @BusquedaLike
                OR P.PER_NombreCompleto LIKE @BusquedaLike
                OR P.PER_Correo LIKE @BusquedaLike
                OR P.PER_Telefono LIKE @BusquedaLike
                OR S.SESION_NombreUsuario LIKE @BusquedaLike
            )
        UNION ALL
        SELECT -- Proveedores sin sesión
            P.PER_Identificacion AS [Identificación]
            , P.PER_NombreCompleto AS [Nombre Completo]
            , P.PER_Telefono AS [Teléfono]
            , P.PER_Correo AS [Correo]
            , P.PER_Direccion AS [Dirección]
            , TP.TIPO_PER_Nombre AS [Tipo Persona]
            , CONVERT(VARCHAR(5), TP.TIPO_PER_DescuentoPct) + '%' AS [Descuento %]
            , 'Proveedor' AS [Rol]
            , 'N/A' AS [Nombre Usuario]
            , CONVERT(VARCHAR(10), P.PER_FechaRegistro, 120) AS [Fecha Registro]
            , CASE 
                WHEN P.PER_Estado = 1 AND PRV.PRV_Estado = 1
                    THEN 'Activo'
                ELSE 
                    'Inactivo'
            END AS [Estado]
        FROM DBO.PERSONAS_TB P
        INNER JOIN DBO.TIPOS_PERSONAS_TB TP
            ON P.PER_TIPO_PER_ID = TP.TIPO_PER_ID
        INNER JOIN DBO.PROVEEDORES_TB PRV
            ON P.PER_ID = PRV.PRV_PER_ID
        -- Excluir proveedores que YA tienen sesión (ya aparecen arriba)
        WHERE P.PER_ID != 1
            AND NOT EXISTS (
                SELECT 1
                FROM DBO.SESIONES_TB S2
                WHERE S2.SESION_PER_ID = P.PER_ID
            )
            AND (   -- Filtro por rol: proveedores solo aparecen en '' o 'PROVEEDORES'
                @RolFiltro IN ('PROVEEDORES', '')
            )
            AND (   -- Filtro por tipo de persona
                @TipoPersonaFiltro IS NULL
                OR TP.TIPO_PER_Nombre = @TipoPersonaFiltro
            )
            AND (   -- Filtro de búsqueda (sin nombre de usuario porque no tienen)
                @Busqueda IS NULL
                OR P.PER_Identificacion LIKE @BusquedaLike
                OR P.PER_NombreCompleto LIKE @BusquedaLike
                OR P.PER_Correo         LIKE @BusquedaLike
                OR P.PER_Telefono       LIKE @BusquedaLike
            )
        ORDER BY [Nombre Completo], [Rol];

        -- Auditoría
        BEGIN TRY
            SET @Descripcion = 'Se usó CONSULTAR_PERSONAS_SP';

            IF @RolFiltro != ''
                SET @Descripcion = @Descripcion + ' con filtro de rol [' + @RolFiltro + ']';

            IF @TipoPersonaFiltro IS NOT NULL
                SET @Descripcion = @Descripcion + ', tipo de persona [' + LEFT(@TipoPersonaFiltro, 20) + ']';

            IF @Busqueda IS NOT NULL
                SET @Descripcion = @Descripcion + ', búsqueda específica [' + LEFT(@Busqueda, 15) + ']';

            IF @RolFiltro = '' AND @TipoPersonaFiltro IS NULL AND @Busqueda IS NULL
                SET @Descripcion = @Descripcion + ' sin filtro específico (Todos).';
            ELSE
                SET @Descripcion = @Descripcion + '.';

            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'PERSONAS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = @Descripcion,
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_PERSONA_SP
    @NombreUsuario      VARCHAR(75)     = NULL,     -- Responsable (NULL = auto-registro - Cliente)
    @Identificacion     VARCHAR(50),                -- Obligatorio
    @NombreCompleto     VARCHAR(150),               -- Obligatorio
    @Telefono           VARCHAR(25)     = NULL,     
    @Correo             VARCHAR(150)    = NULL,     
    @Direccion          VARCHAR(175)    = NULL,     
    @TipoPersona        VARCHAR(50)     = NULL,     -- Obligatorio para Administrador cuando registra (ignorado en auto-registro, Default Cliente)
    @EsProveedor        BIT             = 0         -- 1 = Insertar también en PROVEEDORES_TB
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID_Ejecutor   INT;
    DECLARE @Tipo_Per_ID           INT;
    DECLARE @Persona_ID_Nueva      INT;

    -- Normalización
    SET @Identificacion  = TRIM(ISNULL(@Identificacion, ''));
    SET @NombreCompleto  = TRIM(ISNULL(@NombreCompleto, ''));
    SET @Telefono        = NULLIF(TRIM(@Telefono), '');
    SET @Direccion       = NULLIF(TRIM(@Direccion), '');
    SET @Correo          = NULLIF(TRIM(@Correo), '');
    SET @TipoPersona     = NULLIF(TRIM(@TipoPersona), '');

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validaciones
        IF LEN(@Identificacion) < 9
        BEGIN
            RAISERROR('Error: La identificación debe tener al menos 9 caracteres.', 16, 1);
            RETURN;
        END;

        IF LEN(@NombreCompleto) = 0
        BEGIN
            RAISERROR('Error: El nombre completo no puede estar vacío.', 16, 1);
            RETURN;
        END;

        -- Validar Identificación única 
        IF EXISTS(SELECT 1 FROM DBO.PERSONAS_TB WHERE PER_Identificacion = @Identificacion)
        BEGIN
            RAISERROR('Error: Ya existe una persona registrada con la identificación [%s].', 16, 1, @Identificacion);
            RETURN;
        END;

        -- Validar Correo único
        IF @Correo IS NOT NULL
        BEGIN
            IF EXISTS(SELECT 1 FROM DBO.PERSONAS_TB WHERE PER_Correo = @Correo)
            BEGIN
                RAISERROR('Error: Ya existe una persona registrada con el correo [%s].', 16, 1, @Correo);
                RETURN;
            END;
        END;

        -- Tipo de Registro y Permisos
        IF @NombreUsuario IS NULL
        BEGIN
            -- REGISTRO REALIZADO POR EL MISMO CLIENTE: Solo permitido para Clientes
            IF @EsProveedor = 1
            BEGIN
                RAISERROR('Error: El auto-registro no está disponible para proveedores.', 16, 1);
                RETURN;
            END;

            -- Forzar tipo Cliente Normal
            SET @TipoPersona = 'Cliente Normal';
            
            -- 0 indica al trigger que use el ID de la nueva persona creada
            SET @Persona_ID_Ejecutor = 0;
        END
        ELSE
        BEGIN
            -- REGISTRO REALIZADO POR ADMINISTRADOR
            SELECT @Persona_ID_Ejecutor = S.SESION_PER_ID
            FROM DBO.SESIONES_TB S
            INNER JOIN DBO.ROLES_TB R ON S.SESION_ROL_ID = R.ROL_ID
            WHERE S.SESION_NombreUsuario = @NombreUsuario
                AND S.SESION_Estado = 1
                AND R.ROL_Nombre = 'Administrador';

            IF @Persona_ID_Ejecutor IS NULL
            BEGIN
                RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos de Administrador.', 16, 1, @NombreUsuario);
                RETURN;
            END;

            -- Validar que especificó el Tipo de Persona
            IF @TipoPersona IS NULL
            BEGIN
                RAISERROR('Error: Debe especificar el Tipo de Persona.', 16, 1);
                RETURN;
            END;
        END;

        -- Validación específica para proveedores
        IF @EsProveedor = 1
        BEGIN
            -- Los proveedores deben ser tipo Cliente Normal
            IF @TipoPersona != 'Cliente Normal'
            BEGIN
                RAISERROR('Error: Los proveedores deben ser de tipo [Cliente Normal].', 16, 1);
                RETURN;
            END;
        END;

        -- ID del tipo de Persona
        SELECT @Tipo_Per_ID = TIPO_PER_ID 
        FROM DBO.TIPOS_PERSONAS_TB 
        WHERE TIPO_PER_Nombre = @TipoPersona
            AND TIPO_PER_Estado = 1;

        IF @Tipo_Per_ID IS NULL
        BEGIN
            RAISERROR('Error: Tipo de persona [%s] no encontrado o está inactivo.', 16, 1, @TipoPersona);
            RETURN;
        END;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID_Ejecutor;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_PERSONA_SP';

        -- Insert
        INSERT INTO DBO.PERSONAS_TB (
            PER_Identificacion,
            PER_NombreCompleto,
            PER_Telefono,
            PER_Correo, 
            PER_Direccion,
            PER_TIPO_PER_ID
        )
        VALUES (
            @Identificacion,
            @NombreCompleto,
            @Telefono,
            @Correo,
            @Direccion,
            @Tipo_Per_ID
        );

        SET @Persona_ID_Nueva = SCOPE_IDENTITY();

        -- Insert a PROVEEDORES_TB
        IF @EsProveedor = 1
        BEGIN
            -- Validar que no exista como proveedor (por seguridad)
            IF EXISTS(SELECT 1 FROM DBO.PROVEEDORES_TB WHERE PRV_PER_ID = @Persona_ID_Nueva)
            BEGIN
                RAISERROR('Error: Esta persona ya está registrada como proveedor.', 16, 1);
                RETURN;
            END;

            INSERT INTO DBO.PROVEEDORES_TB (PRV_PER_ID)
            VALUES (@Persona_ID_Nueva);
        END;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH

		IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

    END CATCH;
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_PERSONA_SP
    @NombreUsuario      VARCHAR(75)   = NULL,     -- Auto-modificación = Null, Admin = NombreUsuario de Administrador
    @Identificacion     VARCHAR(50),              -- Identificación de la persona a modificar
    @NuevoNombre        VARCHAR(150)  = NULL,
    @NuevoTelefono      VARCHAR(25)   = NULL,     -- '' = borrar, NULL = no modificar
    @NuevoCorreo        VARCHAR(150)  = NULL,     -- '' = borrar, NULL = no modificar
    @NuevaDireccion     VARCHAR(175)  = NULL,     -- '' = borrar, NULL = no modificar
    @NuevoTipoPersona   VARCHAR(50)   = NULL,     -- Solo Admin puede modificar
    @NuevoEstado        BIT           = NULL      -- Solo Admin puede modificar
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID_Ejecutor  INT;      -- ID de quien ejecuta (para auditoría)
    DECLARE @PER_ID               INT;      -- ID de la persona a modificar
    DECLARE @EsAdministrador      BIT = 0;
    DECLARE @Tipo_Per_ID          INT;

    -- Normalización
    SET @Identificacion = TRIM(ISNULL(@Identificacion, ''));
    SET @NuevoNombre    = NULLIF(TRIM(ISNULL(@NuevoNombre, '')), '');

    BEGIN TRY
        BEGIN TRANSACTION;
        
        IF LEN(@Identificacion) = 0
        BEGIN
            RAISERROR('Error: La identificación no puede estar vacía.', 16, 1);
            RETURN;
        END;

        -- Obtener ID de la persona a modificar
        SELECT @PER_ID = PER_ID
        FROM DBO.PERSONAS_TB
        WHERE PER_Identificacion = @Identificacion;

        IF @PER_ID IS NULL
        BEGIN
            RAISERROR('Error: No existe una persona con la identificación [%s].', 16, 1, @Identificacion);
            RETURN;
        END;

        -- Protección: nadie puede modificar la cuenta SISTEMA
        IF @PER_ID = 1
        BEGIN
            RAISERROR('No se permite modificar la cuenta SISTEMA.', 16, 1);
            RETURN;
        END;

        IF @NombreUsuario IS NULL
        BEGIN
            -- MODO AUTO-MODIFICACIÓN (Persona modificando sus propios datos)
            SET @EsAdministrador = 0;
            
            -- Para auditoría: usamos el ID de la persona misma
            SET @Persona_ID_Ejecutor = @PER_ID;
            
            -- Validar que no intente modificar campos restringidos (Tipo o Estado)
            IF @NuevoTipoPersona IS NOT NULL
            BEGIN
                RAISERROR('Acceso denegado: Solo un Administrador puede modificar el tipo de persona.', 16, 1);
                RETURN;
            END;

            IF @NuevoEstado IS NOT NULL
            BEGIN
                RAISERROR('Acceso denegado: Solo un Administrador puede modificar el estado de la cuenta.', 16, 1);
                RETURN;
            END;
        END
        ELSE
        BEGIN
            -- ADMINISTRADOR (Puede modificar cualquier persona, incluido él mismo)
            SELECT 
                @Persona_ID_Ejecutor = S.SESION_PER_ID,
                @EsAdministrador = CASE WHEN R.ROL_Nombre = 'Administrador' THEN 1 ELSE 0 END
            FROM DBO.SESIONES_TB S
            INNER JOIN DBO.ROLES_TB R ON S.SESION_ROL_ID = R.ROL_ID
            WHERE S.SESION_NombreUsuario = @NombreUsuario
                AND S.SESION_Estado = 1;

            IF @Persona_ID_Ejecutor IS NULL
            BEGIN
                RAISERROR('Error: El usuario [%s] no es válido o no tiene sesión activa.', 16, 1, @NombreUsuario);
                RETURN;
            END;

            IF @EsAdministrador = 0
            BEGIN
                RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos de Administrador.', 16, 1, @NombreUsuario);
                RETURN;
            END;

            -- Opcional: Prevenir que un admin se desactive a sí mismo
            IF @NuevoEstado = 0 AND @Persona_ID_Ejecutor = @PER_ID
            BEGIN
                RAISERROR('Advertencia: No puede desactivar su propia cuenta de administrador.', 16, 1);
                RETURN;
            END;
        END;

        -- Detección de "nada que modificar"
        IF @NuevoNombre IS NULL
            AND @NuevoTelefono IS NULL
            AND @NuevoCorreo IS NULL
            AND @NuevaDireccion IS NULL
            AND @NuevoTipoPersona IS NULL
            AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para la persona con identificación [%s].', 16, 1, @Identificacion);
            RETURN;
        END;

        -- Validar nuevo nombre si se proporcionó
        IF @NuevoNombre IS NOT NULL AND LEN(@NuevoNombre) = 0
        BEGIN
            RAISERROR('Error: El nombre completo no puede estar vacío.', 16, 1);
            RETURN;
        END;

        -- Validar que al borrar teléfono o correo no quede sin ningún contacto
        IF @NuevoTelefono = '' OR @NuevoCorreo = ''
        BEGIN
            DECLARE @TelefonoActual VARCHAR(25);
            DECLARE @CorreoActual   VARCHAR(150);

            SELECT 
                @TelefonoActual = PER_Telefono,
                @CorreoActual   = PER_Correo
            FROM DBO.PERSONAS_TB
            WHERE PER_ID = @PER_ID;

            DECLARE @TelefonoFinal VARCHAR(25) = @TelefonoActual;
            DECLARE @CorreoFinal   VARCHAR(150) = @CorreoActual;

            IF @NuevoTelefono IS NOT NULL SET @TelefonoFinal = NULLIF(@NuevoTelefono, '');
            IF @NuevoCorreo   IS NOT NULL SET @CorreoFinal = NULLIF(@NuevoCorreo, '');

            IF @TelefonoFinal IS NULL AND @CorreoFinal IS NULL
            BEGIN
                RAISERROR('Error: La persona debe tener al menos un medio de contacto (teléfono o correo).', 16, 1);
                RETURN;
            END;
        END;

        -- Validar correo único si se va a cambiar (y no es vacío)
        IF @NuevoCorreo IS NOT NULL AND @NuevoCorreo != ''
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.PERSONAS_TB
                WHERE PER_Correo = @NuevoCorreo
                    AND PER_ID != @PER_ID
            )
            BEGIN
                RAISERROR('Error: Ya existe una persona registrada con el correo [%s].', 16, 1, @NuevoCorreo);
                RETURN;
            END;
        END;

        -- Resolver ID del nuevo tipo de persona si se indicó (solo admin llega aquí)
        IF @NuevoTipoPersona IS NOT NULL
        BEGIN
            SET @NuevoTipoPersona = TRIM(@NuevoTipoPersona);

            IF @NuevoTipoPersona = 'SISTEMA'
            BEGIN
                RAISERROR('Error: No se puede asignar el tipo de persona SISTEMA.', 16, 1);
                RETURN;
            END;

            SELECT @Tipo_Per_ID = TIPO_PER_ID
            FROM DBO.TIPOS_PERSONAS_TB
            WHERE TIPO_PER_Nombre = @NuevoTipoPersona
                AND TIPO_PER_Estado = 1;

            IF @Tipo_Per_ID IS NULL
            BEGIN
                RAISERROR('Error: El tipo de persona [%s] no existe o está inactivo.', 16, 1, @NuevoTipoPersona);
                RETURN;
            END;
        END;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID_Ejecutor;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_PERSONA_SP';

        UPDATE DBO.PERSONAS_TB
        SET
            PER_NombreCompleto = ISNULL(@NuevoNombre, PER_NombreCompleto),
            PER_Telefono = CASE 
                               WHEN @NuevoTelefono IS NULL THEN PER_Telefono
                               WHEN @NuevoTelefono = ''    THEN NULL
                               ELSE @NuevoTelefono
                           END,
            PER_Correo = CASE
                               WHEN @NuevoCorreo IS NULL   THEN PER_Correo
                               WHEN @NuevoCorreo = ''      THEN NULL
                               ELSE @NuevoCorreo
                         END,
            PER_Direccion = CASE
                               WHEN @NuevaDireccion IS NULL THEN PER_Direccion
                               WHEN @NuevaDireccion = ''    THEN NULL
                               ELSE @NuevaDireccion
                         END,
            PER_TIPO_PER_ID = ISNULL(@Tipo_Per_ID, PER_TIPO_PER_ID),
            PER_Estado = ISNULL(@NuevoEstado, PER_Estado)
        WHERE PER_ID = @PER_ID;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH;
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_NOMBRES_PROVEEDORES_SP -- Para ComboBox
    @NombreUsuario  VARCHAR(75)     -- Responsable
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;

    BEGIN TRY

        -- Validación de usuario activo
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Solo nombres de proveedores activos
        SELECT 
            P.PER_NombreCompleto AS [Nombre Proveedor],
            PRV.PRV_Estado AS [Estado]
        FROM DBO.PERSONAS_TB P
        INNER JOIN DBO.PROVEEDORES_TB PRV
            ON P.PER_ID = PRV.PRV_PER_ID
        ORDER BY P.PER_NombreCompleto;

        -- Auditoría
        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'PROVEEDORES_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó CONSULTAR_NOMBRES_PROVEEDORES_SP.',
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_SESION_SP 
    @CreadorCuenta  VARCHAR(75)  = NULL, -- NULL = auto-registro, sino la cuenta la crea un Administrador
    @Identificacion VARCHAR(50),         -- Identificación de la persona a la que se le crea la sesión (tiene CONSTRAINT UNIQUE)
    @NombreUsuario  VARCHAR(75),
    @PasswordHash   VARCHAR(255),
    @NombreRol      VARCHAR(50)
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @CreadorCuenta_ID   INT;
    DECLARE @Persona_ID         INT;
    DECLARE @Rol_ID             INT;
 
    SET @Identificacion = TRIM(ISNULL(@Identificacion, ''));
    SET @NombreUsuario  = TRIM(ISNULL(@NombreUsuario, ''));
    SET @NombreRol      = TRIM(ISNULL(@NombreRol, ''));

    BEGIN TRY

        BEGIN TRANSACTION;

        -- PER_ID a partir de la identificación
        SELECT @Persona_ID = PER_ID
        FROM DBO.PERSONAS_TB
        WHERE PER_Identificacion = @Identificacion
            AND PER_Estado = 1;

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: No existe una persona activa con la identificación [%s].', 16, 1, @Identificacion);
            RETURN;
        END;

        -- la cuenta SISTEMA no puede tener sesiones creadas
        IF @Persona_ID = 1
        BEGIN
            RAISERROR('Error: No se puede crear una sesión para la cuenta SISTEMA.', 16, 1);
            RETURN;
        END;

        -- Validación de permisos del creador
        IF @CreadorCuenta IS NULL
        BEGIN
            -- Auto-registro: la persona se registra a sí misma
            SET @CreadorCuenta_ID = @Persona_ID;
        END
        ELSE 
        BEGIN
            SELECT @CreadorCuenta_ID = S.SESION_PER_ID
            FROM DBO.SESIONES_TB S
            INNER JOIN DBO.ROLES_TB R 
                ON S.SESION_ROL_ID = R.ROL_ID
            WHERE S.SESION_NombreUsuario = @CreadorCuenta
                AND S.SESION_Estado = 1
                AND R.ROL_Nombre = 'Administrador';

            IF @CreadorCuenta_ID IS NULL
            BEGIN
                RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @CreadorCuenta);
                RETURN;
            END;
        END;

        IF LEN(@NombreUsuario) < 1
        BEGIN
            RAISERROR('Error: El nombre de usuario no puede estar vacío.', 16, 1);
            RETURN;
        END;

        -- Validación de nombre de usuario único
        IF EXISTS (
            SELECT 1 
            FROM DBO.SESIONES_TB 
            WHERE SESION_NombreUsuario = @NombreUsuario
        )
        BEGIN
            RAISERROR('Error: El nombre de usuario [%s] ya está registrado.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Validación de hash 
        IF LEN(@PasswordHash) < 1
        BEGIN
            RAISERROR('Error: Hash de la contraseña no válido.', 16, 1);
            RETURN;
        END;

        -- Obtener ID del rol
        SELECT @Rol_ID = ROL_ID 
        FROM DBO.ROLES_TB 
        WHERE ROL_Nombre = @NombreRol
            AND ROL_Estado = 1;
 
        IF @Rol_ID IS NULL
        BEGIN
            RAISERROR('Error: El rol [%s] no existe o está inactivo.', 16, 1, @NombreRol);
            RETURN;
        END;

        -- Restricción: rol 'Sistema' reservado
        IF UPPER(@NombreRol) = 'SISTEMA'
        BEGIN
            RAISERROR('Error: El rol Sistema está reservado para la cuenta del sistema.', 16, 1);
            RETURN;
        END;

        -- Validación de unicidad de rol por persona
        IF EXISTS (
            SELECT 1 
            FROM DBO.SESIONES_TB
            WHERE SESION_PER_ID = @Persona_ID 
                AND SESION_ROL_ID = @Rol_ID
        )
        BEGIN
            RAISERROR('Error: La persona ya tiene una sesión registrada con el rol [%s].', 16, 1, @NombreRol);
            RETURN;
        END;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @CreadorCuenta_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_SESION_SP';
 
        INSERT INTO DBO.SESIONES_TB (SESION_PER_ID, SESION_NombreUsuario, SESION_PwdHash, SESION_ROL_ID)
        VALUES (@Persona_ID, @NombreUsuario, @PasswordHash, @Rol_ID);
 
        COMMIT;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.VERIFICAR_SESION_SP
    @NombreUsuario  VARCHAR(75),
    @PasswordHash   VARCHAR(255)
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Sesion_ID      INT;
    DECLARE @Persona_ID     INT;
    DECLARE @Rol_Nombre     VARCHAR(50);
    DECLARE @Accesos        VARCHAR(500);
    DECLARE @Estado_Sesion  BIT;
    DECLARE @Estado_Persona BIT;
    --DECLARE @Estado_Rol     BIT;

    BEGIN TRY

        -- Normalización
        SET @NombreUsuario = TRIM(ISNULL(@NombreUsuario, ''));
        SET @PasswordHash  = ISNULL(@PasswordHash, '');

        -- Validar parámetros
        IF LEN(@NombreUsuario) = 0
        BEGIN
            RAISERROR('Error: El nombre de usuario no puede estar vacío.', 16, 1);
            RETURN;
        END;

        IF LEN(@PasswordHash) = 0
        BEGIN
            RAISERROR('Error: La contraseña no puede estar vacía.', 16, 1);
            RETURN;
        END;

        -- Buscar sesión con todas las validaciones
        SELECT 
            @Sesion_ID = S.SESION_ID,
            @Persona_ID = S.SESION_PER_ID,
            @Rol_Nombre = R.ROL_Nombre,
            @Accesos = R.ROL_Accesos,
            @Estado_Sesion = S.SESION_Estado,
            @Estado_Persona = P.PER_Estado
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        INNER JOIN DBO.PERSONAS_TB P
            ON S.SESION_PER_ID = P.PER_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_PwdHash = @PasswordHash;

        -- Validar existencia
        IF @Sesion_ID IS NULL
        BEGIN
            RAISERROR('Error: Credenciales incorrectas.', 16, 1);
            RETURN;
        END;

        -- Validar estados
        IF @Estado_Persona = 0
        BEGIN
            RAISERROR('Error: La persona está inactiva. Contacte al administrador.', 16, 1);
            RETURN;
        END;

        IF @Estado_Sesion = 0
        BEGIN
            RAISERROR('Error: La cuenta está desactivada. Contacte al administrador.', 16, 1);
            RETURN;
        END;

        /*IF @Estado_Rol = 0
        BEGIN
            RAISERROR('Error: El rol asignado está inactivo. Contacte al administrador.', 16, 1);
            RETURN;
        END;*/

        -- Éxito: Retornar datos del usuario
        SELECT 
            S.SESION_NombreUsuario AS [Nombre Usuario],
            P.PER_NombreCompleto AS [Nombre Completo],
            R.ROL_Nombre AS [Rol],
            R.ROL_Accesos AS [Accesos]
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.PERSONAS_TB P
            ON S.SESION_PER_ID = P.PER_ID
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_ID = @Sesion_ID;

        -- Auditoría de login exitoso
        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'SESIONES_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó VERIFICAR_SESION_SP.',
                @Antes          = NULL,
                @Despues        = NULL
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no interrumpe el login
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_SESION_SP
    @NombreUsuario      VARCHAR(75),            -- Responsable
    @NombreUsuarioCuenta VARCHAR(75),           -- Cuenta a modificar (Nombre de Usuario)
    @NuevoNombreUsuario VARCHAR(75)  = NULL,    -- NULL = no modificar
    @NuevoPasswordHash  VARCHAR(255) = NULL,    -- NULL = no modificar
    @NuevoRol           VARCHAR(50)  = NULL,    -- Solo Administrador puede modificarlo
    @NuevoEstado        BIT          = NULL     -- Solo Administrador puede modificarlo
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID        INT;
    DECLARE @EsAdministrador   BIT = 0;
    DECLARE @SESION_ID         INT;
    DECLARE @SESION_PER_ID     INT;
    DECLARE @Rol_ID            INT;

    SET @NombreUsuarioCuenta = TRIM(ISNULL(@NombreUsuarioCuenta, ''));
    SET @NuevoNombreUsuario  = NULLIF(TRIM(ISNULL(@NuevoNombreUsuario, '')), '');
    SET @NuevoPasswordHash   = NULLIF(TRIM(ISNULL(@NuevoPasswordHash,  '')), '');

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Validación de usuario activo y detección de rol
        SELECT
            @Persona_ID = S.SESION_PER_ID,
            @EsAdministrador = CASE WHEN R.ROL_Nombre = 'Administrador' THEN 1 ELSE 0 END
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Obtener datos de la cuenta a modificar
        SELECT
            @SESION_ID = S.SESION_ID,
            @SESION_PER_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        WHERE S.SESION_NombreUsuario = @NombreUsuarioCuenta;

        IF @SESION_ID IS NULL
        BEGIN
            RAISERROR('Error: La cuenta [%s] no existe.', 16, 1, @NombreUsuarioCuenta);
            RETURN;
        END;

        -- Protección: la cuenta SISTEMA no se puede modificar
        IF @SESION_PER_ID = 1
        BEGIN
            RAISERROR('No se permite modificar la cuenta SISTEMA.', 16, 1);
            RETURN;
        END;

        -- Un persona que no sea Administrador solo puede modificar su propia cuenta
        IF @EsAdministrador = 0 AND @Persona_ID != @SESION_PER_ID
        BEGIN
            RAISERROR('Acceso denegado: Solo puede modificar su propia cuenta.', 16, 1);
            RETURN;
        END;

        -- Solo Administrador puede cambiar el rol
        IF @NuevoRol IS NOT NULL AND @EsAdministrador = 0
        BEGIN
            RAISERROR('Acceso denegado: Solo un Administrador puede modificar el rol de una cuenta.', 16, 1);
            RETURN;
        END;

        -- Solo Administrador puede activar o desactivar la cuenta
        IF @NuevoEstado IS NOT NULL AND @EsAdministrador = 0
        BEGIN
            RAISERROR('Acceso denegado: Solo un Administrador puede activar o desactivar una cuenta.', 16, 1);
            RETURN;
        END;

        -- Nada que modificar
        IF @NuevoNombreUsuario IS NULL
            AND @NuevoPasswordHash IS NULL
            AND @NuevoRol          IS NULL
            AND @NuevoEstado       IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para la cuenta [%s].', 16, 1, @NombreUsuarioCuenta);
            RETURN;
        END;

        -- Validar que el nuevo nombre de usuario no esté en uso
        IF @NuevoNombreUsuario IS NOT NULL
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.SESIONES_TB
                WHERE SESION_NombreUsuario = @NuevoNombreUsuario
                    AND SESION_ID != @SESION_ID
            )
            BEGIN
                RAISERROR('Error: El nombre de usuario [%s] ya está registrado.', 16, 1, @NuevoNombreUsuario);
                RETURN;
            END;
        END;

        -- Resolver y validar el nuevo rol
        IF @NuevoRol IS NOT NULL
        BEGIN
            SET @NuevoRol = TRIM(@NuevoRol);

            IF UPPER(@NuevoRol) = 'SISTEMA'
            BEGIN
                RAISERROR('Error: El rol Sistema está reservado para la cuenta del sistema.', 16, 1);
                RETURN;
            END;

            SELECT @Rol_ID = ROL_ID
            FROM DBO.ROLES_TB
            WHERE ROL_Nombre = @NuevoRol
                AND ROL_Estado = 1;

            IF @Rol_ID IS NULL
            BEGIN
                RAISERROR('Error: El rol [%s] no existe o está inactivo.', 16, 1, @NuevoRol);
                RETURN;
            END;

            -- La persona no puede debe ese rol en otra cuenta
            IF EXISTS (
                SELECT 1
                FROM DBO.SESIONES_TB
                WHERE SESION_PER_ID = @SESION_PER_ID
                    AND SESION_ROL_ID = @Rol_ID
                    AND SESION_ID != @SESION_ID
            )
            BEGIN
                RAISERROR('Error: La persona ya tiene otra cuenta registrada con el rol [%s].', 16, 1, @NuevoRol);
                RETURN;
            END;
        END;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_SESION_SP';

        UPDATE DBO.SESIONES_TB
        SET
            SESION_NombreUsuario = ISNULL(@NuevoNombreUsuario, SESION_NombreUsuario),
            SESION_PwdHash       = ISNULL(@NuevoPasswordHash,  SESION_PwdHash),
            SESION_ROL_ID        = ISNULL(@Rol_ID,             SESION_ROL_ID),
            SESION_Estado        = ISNULL(@NuevoEstado,        SESION_Estado)
        WHERE SESION_ID = @SESION_ID;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_ESTADOS_ENTREGAS_SP
    @NombreUsuario  VARCHAR(75)     -- Responsable
AS
BEGIN
 
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT;
 
    BEGIN TRY
 
        -- Validación de usuario activo
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;
 
        SELECT
            EST_ENT_Nombre AS [Estado Entrega]
            , CASE
                WHEN EST_ENT_Estado = 1
                    THEN 'Activo'
                ELSE
                    'Inactivo'
            END AS [Estado]
        FROM DBO.ESTADOS_ENTREGAS_TB;
 
        -- Auditoría
        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'ESTADOS_ENTREGAS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = 'Se usó CONSULTAR_ESTADOS_ENTREGAS_SP.',
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH
 
    END TRY
    BEGIN CATCH
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_ESTADO_ENTREGA_SP
    @NombreUsuario  VARCHAR(75),    -- Responsable
    @Nombre         VARCHAR(50)     -- Nombre del nuevo estado
AS
BEGIN
 
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID INT;
    SET @Nombre = TRIM(ISNULL(@Nombre, ''));
 
    BEGIN TRY
 
        BEGIN TRANSACTION;
 
        -- Validación de permisos y obtención de ID
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;
 
        IF LEN(@Nombre) <= 0
        BEGIN
            RAISERROR('Error: El nombre del estado de entrega no es válido.', 16, 1);
            RETURN;
        END;
 
        IF EXISTS (
            SELECT 1
            FROM DBO.ESTADOS_ENTREGAS_TB
            WHERE EST_ENT_Nombre = @Nombre
        )
        BEGIN
            RAISERROR('Error: El estado de entrega [%s] ya se encuentra registrado.', 16, 1, @Nombre);
            RETURN;
        END;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_ESTADO_ENTREGA_SP';
 
        INSERT INTO DBO.ESTADOS_ENTREGAS_TB (EST_ENT_Nombre)
        VALUES (@Nombre);
 
        COMMIT;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
    END TRY
    BEGIN CATCH
 
        IF @@TRANCOUNT > 0 ROLLBACK;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_ESTADO_ENTREGA_SP
    @NombreUsuario  VARCHAR(75),            -- Responsable
    @Nombre         VARCHAR(50),            -- Nombre actual del estado a modificar
    @NuevoNombre    VARCHAR(50)  = NULL,
    @NuevoEstado    BIT          = NULL
AS
BEGIN
 
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID   INT;
    DECLARE @EST_ENT_ID   INT;
 
    SET @Nombre      = TRIM(ISNULL(@Nombre, ''));
    SET @NuevoNombre = TRIM(ISNULL(@NuevoNombre, ''));
 
    BEGIN TRY
 
        BEGIN TRANSACTION;
 
        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';
 
        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;
 
        -- Obtener ID del estado a modificar
        SELECT @EST_ENT_ID = EST_ENT_ID
        FROM DBO.ESTADOS_ENTREGAS_TB
        WHERE EST_ENT_Nombre = @Nombre;
 
        IF @EST_ENT_ID IS NULL
        BEGIN
            RAISERROR('Error: El estado de entrega [%s] no existe.', 16, 1, @Nombre);
            RETURN;
        END;
 
        -- Detectar si no se pasó ningún cambio
        IF LEN(@NuevoNombre) = 0
            AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para el estado de entrega [%s].', 16, 1, @Nombre);
            RETURN;
        END;
 
        -- Validar que el nuevo nombre no esté en uso por otro estado
        IF LEN(@NuevoNombre) > 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.ESTADOS_ENTREGAS_TB
                WHERE EST_ENT_Nombre = @NuevoNombre
                    AND EST_ENT_ID != @EST_ENT_ID
            )
            BEGIN
                RAISERROR('Error: Ya existe un estado de entrega con el nombre [%s].', 16, 1, @NuevoNombre);
                RETURN;
            END;
        END;
 
        -- Validación para desactivar estado en uso (opcional, comentado como en tus otros SP)
        /*
        IF @NuevoEstado = 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.ENC_ENTREGAS_CLIENTES_TB
                WHERE ENC_ENT_CLI_EST_ENT_ID = @EST_ENT_ID
            )
            BEGIN
                RAISERROR('No se puede desactivar el estado porque hay entregas asignadas.', 16, 1);
                RETURN;
            END;
        END;
        */
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_ESTADO_ENTREGA_SP';
 
        UPDATE DBO.ESTADOS_ENTREGAS_TB
        SET
            EST_ENT_Nombre = ISNULL(NULLIF(@NuevoNombre, ''), EST_ENT_Nombre),
            EST_ENT_Estado = ISNULL(@NuevoEstado, EST_ENT_Estado)
        WHERE EST_ENT_ID = @EST_ENT_ID;
 
        COMMIT;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
    END TRY
    BEGIN CATCH
 
        IF @@TRANCOUNT > 0 ROLLBACK;
 
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();
 
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
 
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_DESCUENTO_SP
    @NombreUsuario          VARCHAR(75),    -- Responsable
    @NombreComercial        VARCHAR(100),
    @Descripcion            VARCHAR(175),
    @Categoria              VARCHAR(75),
    @Porcentaje             DECIMAL(5,2),
    @FechaInicio            DATE,
    @FechaFinal             DATE
AS
BEGIN
    
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID     INT;
    DECLARE @CAT_DESC_ID    INT;

    SET @NombreComercial = TRIM(ISNULL(@NombreComercial, ''));
    SET @Descripcion     = TRIM(ISNULL(@Descripcion, ''));
    SET @Categoria       = TRIM(ISNULL(@Categoria, ''));

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Validación de permisos y obtención de ID
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Validar nombre comercial
        IF LEN(@NombreComercial) = 0
        BEGIN
            RAISERROR('Error: El nombre comercial no puede estar vacío.', 16, 1);
            RETURN;
        END;

        -- Validar descripción
        IF LEN(@Descripcion) = 0
        BEGIN
            RAISERROR('Error: La descripción no puede estar vacía.', 16, 1);
            RETURN;
        END;

        -- Validar categoría
        IF LEN(@Categoria) = 0
        BEGIN
            RAISERROR('Error: La categoría no puede estar vacía.', 16, 1);
            RETURN;
        END;

        -- Obtener ID de la categoría
        SELECT @CAT_DESC_ID = CAT_DESC_ID
        FROM DBO.CAT_DESCUENTOS_TB
        WHERE CAT_DESC_Nombre = @Categoria
            AND CAT_DESC_Estado = 1;

        IF @CAT_DESC_ID IS NULL
        BEGIN
            RAISERROR('Error: La categoría [%s] no existe o está inactiva.', 16, 1, @Categoria);
            RETURN;
        END;

        -- Validar porcentaje
        IF @Porcentaje < 0 OR @Porcentaje > 100
        BEGIN
            RAISERROR('Error: El porcentaje de descuento debe estar entre 0 y 100.', 16, 1);
            RETURN;
        END;

        -- Validar fechas
        IF @FechaInicio IS NULL
        BEGIN
            RAISERROR('Error: La fecha de inicio no puede estar vacía.', 16, 1);
            RETURN;
        END;

        IF @FechaFinal IS NULL
        BEGIN
            RAISERROR('Error: La fecha final no puede estar vacía.', 16, 1);
            RETURN;
        END;

        IF @FechaFinal <= @FechaInicio
        BEGIN
            RAISERROR('Error: La fecha final debe ser posterior a la fecha de inicio.', 16, 1);
            RETURN;
        END;

        -- Validar que no exista un descuento con el mismo nombre comercial
        IF EXISTS (
            SELECT 1 
            FROM DBO.DESCUENTOS_TB 
            WHERE DESC_NombreComercial = @NombreComercial
        )
        BEGIN
            RAISERROR('Error: Ya existe un descuento con el nombre comercial [%s].', 16, 1, @NombreComercial);
            RETURN;
        END;

        -- Preparar contexto para auditoría
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_DESCUENTO_SP';

        -- Insertar descuento
        INSERT INTO DBO.DESCUENTOS_TB (
            DESC_NombreComercial,
            DESC_Descripcion,
            DESC_CAT_DESC_ID,
            DESC_DescuentoPct,
            DESC_FechaInicio,
            DESC_FechaFin
        )
        VALUES (
            @NombreComercial,
            @Descripcion,
            @CAT_DESC_ID,
            @Porcentaje,
            @FechaInicio,
            @FechaFinal
        );

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH
        
        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_DESCUENTOS_SP
    @NombreUsuario      VARCHAR(75)  = NULL,        -- Responsable
    @CategoriaFiltro    VARCHAR(75)  = NULL, -- Filtro por nombre de categoría
    @FechaDesde         DATE         = NULL, -- Rango inicio
    @FechaHasta         DATE         = NULL  -- Rango fin
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID     INT;
    DECLARE @Descripcion    VARCHAR(250);
    DECLARE @FechaHoy       DATE = CAST(GETDATE() AS DATE);

    BEGIN TRY

        IF @NombreUsuario IS NULL
        BEGIN
            SET @Persona_ID = 1; -- Fallback al sistema
        END
        ELSE
        BEGIN
            -- Validación de usuario activo
            SELECT @Persona_ID = S.SESION_PER_ID
            FROM DBO.SESIONES_TB S
            INNER JOIN DBO.ROLES_TB R
                ON S.SESION_ROL_ID = R.ROL_ID
            WHERE S.SESION_NombreUsuario = @NombreUsuario
                AND S.SESION_Estado = 1;

            IF @Persona_ID IS NULL
            BEGIN
                RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
                RETURN;
            END;
        END;

        -- Validar coherencia de fechas de filtro
        IF @FechaDesde IS NOT NULL AND @FechaHasta IS NOT NULL
           AND @FechaHasta < @FechaDesde
        BEGIN
            RAISERROR('Error: La fecha hasta no puede ser anterior a la fecha desde.', 16, 1);
            RETURN;
        END;

        -- Consulta principal con indicadores de vigencia temporal únicamente
        SELECT 
            D.DESC_NombreComercial AS [Nombre Comercial],
            D.DESC_Descripcion AS [Descripción],
            C.CAT_DESC_Nombre AS [Categoría],
            CONVERT(VARCHAR(5), D.DESC_DescuentoPct) + '%' AS [Porcentaje],
            CONVERT(VARCHAR(10), D.DESC_FechaInicio, 120) AS [Fecha Inicio],
            CONVERT(VARCHAR(10), D.DESC_FechaFin, 120) AS [Fecha Fin],
            -- Solo vigencia temporal basada en fechas, no en estado del registro
            CASE  
                WHEN @FechaHoy < D.DESC_FechaInicio THEN 'Pendiente'
                WHEN @FechaHoy > D.DESC_FechaFin THEN 'Vencido'
                ELSE 'Vigente'
            END AS [Estado Vigencia],
            -- Días calculados según vigencia
            CASE 
                WHEN @FechaHoy < D.DESC_FechaInicio THEN DATEDIFF(DAY, @FechaHoy, D.DESC_FechaInicio)
                WHEN @FechaHoy > D.DESC_FechaFin THEN DATEDIFF(DAY, D.DESC_FechaFin, @FechaHoy) * -1
                ELSE DATEDIFF(DAY, @FechaHoy, D.DESC_FechaFin)
            END AS [Días],
            CASE 
                WHEN D.DESC_Estado = 1
                    THEN 'Activo'
                ELSE
                    'Inactivo'
            END AS [Estado]
        FROM DBO.DESCUENTOS_TB D
        INNER JOIN DBO.CAT_DESCUENTOS_TB C
            ON D.DESC_CAT_DESC_ID = C.CAT_DESC_ID
        WHERE 
            -- Filtro por categoría
            (@CategoriaFiltro IS NULL OR C.CAT_DESC_Nombre = @CategoriaFiltro)
            -- Filtro por rango de fechas
            AND (
                @FechaDesde IS NULL 
                OR @FechaHasta IS NULL
                OR (D.DESC_FechaInicio <= @FechaHasta AND D.DESC_FechaFin >= @FechaDesde)
            )
        ORDER BY 
            -- Orden: Vigentes primero, luego pendientes, luego vencidos
            CASE 
                WHEN @FechaHoy BETWEEN D.DESC_FechaInicio AND D.DESC_FechaFin THEN 0
                WHEN @FechaHoy < D.DESC_FechaInicio THEN 1
                ELSE 2
            END,
            D.DESC_FechaInicio DESC;

        -- Auditoría
        BEGIN TRY
            -- Construir descripción paso a paso para evitar errores de precedencia
            SET @Descripcion = 'Se usó CONSULTAR_DESCUENTOS_SP';
            
            IF @CategoriaFiltro IS NOT NULL 
                SET @Descripcion = @Descripcion + ' con categoría [' + LEFT(@CategoriaFiltro, 30) + '].';
            ELSE 
                SET @Descripcion = @Descripcion + ' sin filtro específico (Todos).';
            
            IF @FechaDesde IS NOT NULL AND @FechaHasta IS NOT NULL 
                SET @Descripcion = @Descripcion + ' Rango de fechas [' + CONVERT(VARCHAR(10), @FechaDesde, 120) + ' a ' + CONVERT(VARCHAR(10), @FechaHasta, 120) + '].';
            ELSE IF @FechaDesde IS NOT NULL 
                SET @Descripcion = @Descripcion + ' Desde [' + CONVERT(VARCHAR(10), @FechaDesde, 120) + '].';
            ELSE IF @FechaHasta IS NOT NULL 
                SET @Descripcion = @Descripcion + ' Hasta [' + CONVERT(VARCHAR(10), @FechaHasta, 120) + '].';

            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'DESCUENTOS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = @Descripcion,
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_DESCUENTO_SP
    @NombreUsuario          VARCHAR(75),
    @NombreComercial        VARCHAR(100),
    @NuevoNombreComercial   VARCHAR(100)    = NULL,
    @NuevaDescripcion       VARCHAR(175)    = NULL,
    @NuevaCategoria         VARCHAR(75)     = NULL,
    @NuevoPorcentaje        DECIMAL(5,2)    = NULL,
    @NuevaFechaInicio       DATE            = NULL,
    @NuevaFechaFin          DATE            = NULL,
    @NuevoEstado            BIT             = NULL
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID         INT;
    DECLARE @DESC_ID            INT;
    DECLARE @CAT_DESC_ID_Actual INT;
    DECLARE @CAT_DESC_ID_Nueva  INT;
    DECLARE @FechaInicioFinal   DATE;
    DECLARE @FechaFinFinal      DATE;

    SET @NombreComercial        = TRIM(ISNULL(@NombreComercial, ''));
    SET @NuevoNombreComercial   = TRIM(ISNULL(@NuevoNombreComercial, ''));
    SET @NuevaDescripcion       = TRIM(ISNULL(@NuevaDescripcion, ''));
    SET @NuevaCategoria         = TRIM(ISNULL(@NuevaCategoria, ''));

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Obtener datos actuales del descuento
        SELECT
            @DESC_ID = DESC_ID,
            @CAT_DESC_ID_Actual = DESC_CAT_DESC_ID,
            @FechaInicioFinal = DESC_FechaInicio,
            @FechaFinFinal = DESC_FechaFin
        FROM DBO.DESCUENTOS_TB
        WHERE DESC_NombreComercial = @NombreComercial;

        IF @DESC_ID IS NULL
        BEGIN
            RAISERROR('Error: El descuento [%s] no existe.', 16, 1, @NombreComercial);
            RETURN;
        END;

        -- Verificar que se especificó al menos un cambio
        IF LEN(@NuevoNombreComercial) = 0
            AND LEN(@NuevaDescripcion) = 0
            AND LEN(@NuevaCategoria) = 0
            AND @NuevoPorcentaje IS NULL
            AND @NuevaFechaInicio IS NULL
            AND @NuevaFechaFin IS NULL
            AND @NuevoEstado IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para el descuento [%s].', 16, 1, @NombreComercial);
            RETURN;
        END;

        -- Validar nuevo nombre comercial no duplicado
        IF LEN(@NuevoNombreComercial) > 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM DBO.DESCUENTOS_TB
                WHERE DESC_NombreComercial = @NuevoNombreComercial
                    AND DESC_ID != @DESC_ID
            )
            BEGIN
                RAISERROR('Error: Ya existe un descuento con el nombre comercial [%s].', 16, 1, @NuevoNombreComercial);
                RETURN;
            END;
        END;

        -- Validar nueva categoría
        IF LEN(@NuevaCategoria) > 0
        BEGIN
            SELECT @CAT_DESC_ID_Nueva = CAT_DESC_ID
            FROM DBO.CAT_DESCUENTOS_TB
            WHERE CAT_DESC_Nombre = @NuevaCategoria
                AND CAT_DESC_Estado = 1;

            IF @CAT_DESC_ID_Nueva IS NULL
            BEGIN
                RAISERROR('Error: La categoría [%s] no existe o está inactiva.', 16, 1, @NuevaCategoria);
                RETURN;
            END;
        END;

        -- Validar porcentaje
        IF @NuevoPorcentaje IS NOT NULL
            AND (@NuevoPorcentaje < 0.00 OR @NuevoPorcentaje > 100.00)
        BEGIN
            RAISERROR('Error: El porcentaje debe estar entre 0 y 100.', 16, 1);
            RETURN;
        END;

        -- Calcular fechas finales para validar coherencia
        IF @NuevaFechaInicio IS NOT NULL
            SET @FechaInicioFinal = @NuevaFechaInicio;

        IF @NuevaFechaFin IS NOT NULL
            SET @FechaFinFinal = @NuevaFechaFin;

        IF @FechaFinFinal <= @FechaInicioFinal
        BEGIN
            RAISERROR('Error: La fecha fin debe ser posterior a la fecha inicio.', 16, 1);
            RETURN;
        END;

        -- Preparar contexto para auditoría
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_DESCUENTO_SP';

        UPDATE DBO.DESCUENTOS_TB
        SET
            DESC_NombreComercial = ISNULL(NULLIF(@NuevoNombreComercial, ''), DESC_NombreComercial),
            DESC_Descripcion     = ISNULL(NULLIF(@NuevaDescripcion, ''), DESC_Descripcion),
            DESC_CAT_DESC_ID     = ISNULL(@CAT_DESC_ID_Nueva, DESC_CAT_DESC_ID),
            DESC_DescuentoPct    = ISNULL(@NuevoPorcentaje, DESC_DescuentoPct),
            DESC_FechaInicio     = ISNULL(@NuevaFechaInicio, DESC_FechaInicio),
            DESC_FechaFin        = ISNULL(@NuevaFechaFin, DESC_FechaFin),
            DESC_Estado          = ISNULL(@NuevoEstado, DESC_Estado)
        WHERE DESC_ID = @DESC_ID;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_PRODUCTO_SP
    @NombreUsuario      VARCHAR(75),
    @RutaImagen         VARCHAR(275),
    @Descripcion        VARCHAR(150),
    @TipoProducto       VARCHAR(75),    -- Nombre del tipo de producto
    @MarcaProducto      VARCHAR(75),    -- Nombre de la marca
    @NombreProveedor    VARCHAR(150),   -- Nombre Completo del Proveedor
    @PrecioCompra       DECIMAL(10,2),
    @PrecioVenta        DECIMAL(10,2),
    @NombreUbicacion    VARCHAR(75),    -- Ubicación del Inventario
    @CantidadIngreso    INT,            -- Cantidad a Ingresar al inventario
    @StockMinimo        INT,            -- Solo aplica si es producto nuevo en esa ubicación
    @NombreDescuento    VARCHAR(100)    = NULL -- NULL = sin descuento
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID  INT;
    DECLARE @TIPO_PRD_ID INT;
    DECLARE @MARC_PRD_ID INT;
    DECLARE @PRV_ID      INT;
    DECLARE @PRD_ID      INT;
    DECLARE @UBI_INV_ID  INT;
    DECLARE @DESC_ID     INT;
    DECLARE @FechaHoy    DATE = CAST(GETDATE() AS DATE);

    -- Normalización
    SET @RutaImagen      = TRIM(ISNULL(@RutaImagen, ''));
    SET @Descripcion     = TRIM(ISNULL(@Descripcion, ''));
    SET @TipoProducto    = TRIM(ISNULL(@TipoProducto, ''));
    SET @MarcaProducto   = TRIM(ISNULL(@MarcaProducto, ''));
    SET @NombreProveedor = TRIM(ISNULL(@NombreProveedor, ''));
    SET @NombreUbicacion = TRIM(ISNULL(@NombreUbicacion, ''));
    SET @NombreDescuento = NULLIF(TRIM(@NombreDescuento), '');

    BEGIN TRY
        
        BEGIN TRANSACTION;

        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Validación de parámetros
        IF LEN(@RutaImagen) = 0
        BEGIN
            RAISERROR('Error: La ruta de imagen no puede estar vacía.', 16, 1);
            RETURN;
        END;

        IF LEN(@Descripcion) = 0
        BEGIN
            RAISERROR('Error: La descripción del producto no puede estar vacía.', 16, 1);
            RETURN;
        END;

        IF LEN(@TipoProducto) = 0
        BEGIN
            RAISERROR('Error: El tipo de producto no puede estar vacío.', 16, 1);
            RETURN;
        END;

        IF LEN(@MarcaProducto) = 0
        BEGIN
            RAISERROR('Error: La marca no puede estar vacía.', 16, 1);
            RETURN;
        END;

        IF LEN(@NombreProveedor) = 0
        BEGIN
            RAISERROR('Error: El nombre del proveedor no puede estar vacío.', 16, 1);
            RETURN;
        END;

        IF LEN(@NombreUbicacion) = 0
        BEGIN
            RAISERROR('Error: La ubicación no puede estar vacía.', 16, 1);
            RETURN;
        END;

        IF @PrecioCompra < 0
        BEGIN
            RAISERROR('Error: El precio de compra no puede ser negativo.', 16, 1);
            RETURN;
        END;

        IF @PrecioVenta <= 0
        BEGIN
            RAISERROR('Error: El precio de venta debe ser mayor a 0.', 16, 1);
            RETURN;
        END;

        IF @PrecioVenta < @PrecioCompra
        BEGIN
            RAISERROR('Error: El precio de venta no puede ser menor al precio de compra.', 16, 1);
            RETURN;
        END;

        IF @CantidadIngreso <= 0
        BEGIN
            RAISERROR('Error: La cantidad de ingreso debe ser mayor a 0.', 16, 1);
            RETURN;
        END;

        IF @StockMinimo < 0
        BEGIN
            RAISERROR('Error: El stock mínimo no puede ser negativo.', 16, 1);
            RETURN;
        END;

        -- Foreign keys
        -- Tipo de producto
        SELECT @TIPO_PRD_ID = TIPO_PRD_ID
        FROM DBO.TIPOS_PRODUCTOS_TB
        WHERE TIPO_PRD_Nombre = @TipoProducto
            AND TIPO_PRD_Estado = 1;

        IF @TIPO_PRD_ID IS NULL
        BEGIN
            RAISERROR('Error: El tipo de producto [%s] no existe o está inactivo.', 16, 1, @TipoProducto);
            RETURN;
        END;

        -- Marca
        SELECT @MARC_PRD_ID = MARC_PRD_ID
        FROM DBO.MARCAS_PRODUCTOS_TB
        WHERE MARC_PRD_Nombre = @MarcaProducto
            AND MARC_PRD_Estado = 1;

        IF @MARC_PRD_ID IS NULL
        BEGIN
            RAISERROR('Error: La marca [%s] no existe o está inactiva.', 16, 1, @MarcaProducto);
            RETURN;
        END;

        -- Proveedor
        SELECT @PRV_ID = PRV.PRV_ID
        FROM DBO.PROVEEDORES_TB PRV
        INNER JOIN DBO.PERSONAS_TB P
            ON PRV.PRV_PER_ID = P.PER_ID
        WHERE P.PER_NombreCompleto = @NombreProveedor
            AND PRV.PRV_Estado = 1
            AND P.PER_Estado = 1;

        IF @PRV_ID IS NULL
        BEGIN
            RAISERROR('Error: El proveedor [%s] no existe o está inactivo.', 16, 1, @NombreProveedor);
            RETURN;
        END;

        -- Ubicación
        SELECT @UBI_INV_ID = UBI_INV_ID
        FROM DBO.UBI_INVENTARIOS_TB
        WHERE UBI_INV_Nombre = @NombreUbicacion
            AND UBI_INV_Estado = 1;

        IF @UBI_INV_ID IS NULL
        BEGIN
            RAISERROR('Error: La ubicación [%s] no existe o está inactiva.', 16, 1, @NombreUbicacion);
            RETURN;
        END;

        -- Descuento (Parametro opcional)
        IF @NombreDescuento IS NOT NULL
        BEGIN
            SELECT @DESC_ID = DESC_ID
            FROM DBO.DESCUENTOS_TB
            WHERE DESC_NombreComercial = @NombreDescuento
                AND DESC_Estado = 1
                AND @FechaHoy <= DESC_FechaFin;

            IF @DESC_ID IS NULL
            BEGIN
                RAISERROR('Error: El descuento [%s] no existe, está inactivo o no está vigente.', 16, 1, @NombreDescuento);
                RETURN;
            END;
        END;

        -- Intentar obtener el PRD_ID si el producto ya existe
        SELECT @PRD_ID = PRD_ID
        FROM DBO.PRODUCTOS_TB
        WHERE PRD_Descripcion  = @Descripcion
            AND PRD_TIPO_PRD_ID = @TIPO_PRD_ID
            AND PRD_MARC_PRD_ID = @MARC_PRD_ID
            AND PRD_PRV_ID      = @PRV_ID;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_PRODUCTO_SP';

        IF @PRD_ID IS NULL
        BEGIN
            -- Producto Nuevo
            INSERT INTO DBO.PRODUCTOS_TB (
                PRD_RutaImagen,
                PRD_Descripcion,
                PRD_TIPO_PRD_ID,
                PRD_MARC_PRD_ID,
                PRD_PRV_ID,
                PRD_DESC_ID,
                PRD_PrecioCompra,
                PRD_PrecioVenta
            )
            VALUES (
                @RutaImagen,
                @Descripcion,
                @TIPO_PRD_ID,
                @MARC_PRD_ID,
                @PRV_ID,
                @DESC_ID,
                @PrecioCompra,
                @PrecioVenta
            );

            SET @PRD_ID = SCOPE_IDENTITY();

            INSERT INTO DBO.INVENTARIOS_TB (
                INV_UBI_INV_ID,
                INV_PRD_ID,
                INV_StockMinimo,
                INV_StockActual
            )
            VALUES (
                @UBI_INV_ID,
                @PRD_ID,
                @StockMinimo,
                @CantidadIngreso
            );
        END
        ELSE
        BEGIN
            -- El producto ya existe; verificar si ya está registrado en la ubicación indicada
            IF EXISTS (
                SELECT 1
                FROM DBO.INVENTARIOS_TB
                WHERE INV_PRD_ID     = @PRD_ID
                    AND INV_UBI_INV_ID = @UBI_INV_ID
            )
            BEGIN
                -- Producto registrado en la ubicación indicada
                RAISERROR('Error: El producto ya está registrado en la ubicación [%s].', 16, 1, @NombreUbicacion);
                RETURN;
            END;

            -- Producto existe pero ubicación diferente
            INSERT INTO DBO.INVENTARIOS_TB (
                INV_UBI_INV_ID,
                INV_PRD_ID,
                INV_StockMinimo,
                INV_StockActual
            )
            VALUES (
                @UBI_INV_ID,
                @PRD_ID,
                @StockMinimo,
                @CantidadIngreso
            );
        END;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH
        
        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_PRODUCTOS_SP
    @NombreUsuario      VARCHAR(75)     = NULL,        -- Responsable
    @FiltroDescripcion  VARCHAR(150)    = NULL, -- Búsqueda parcial en descripción
    @FiltroTipo         VARCHAR(75)     = NULL, -- Nombre exacto del tipo de producto
    @FiltroMarca        VARCHAR(75)     = NULL, -- Nombre exacto de la marca
    @FiltroProveedor    VARCHAR(150)    = NULL, -- Nombre exacto del proveedor
    @FiltroDescuento    VARCHAR(100)    = NULL  -- Nombre exacto del descuento comercial
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;
    DECLARE @FechaHoy   DATE = CAST(GETDATE() AS DATE);

    BEGIN TRY
        
        IF @NombreUsuario IS NULL
        BEGIN
            SET @Persona_ID = 1; -- Fallback al sistema
        END
        ELSE
        BEGIN
            -- Validación de usuario
            SELECT @Persona_ID = S.SESION_PER_ID
            FROM DBO.SESIONES_TB S
            INNER JOIN DBO.ROLES_TB R
                ON S.SESION_ROL_ID = R.ROL_ID
            WHERE S.SESION_NombreUsuario = @NombreUsuario
                AND S.SESION_Estado = 1;

            IF @Persona_ID IS NULL
            BEGIN
                RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
                RETURN;
            END;
        END

        -- Normalización de filtros, todo opcional
        SET @FiltroDescripcion  = NULLIF(TRIM(ISNULL(@FiltroDescripcion, '')), '');
        SET @FiltroTipo         = NULLIF(TRIM(ISNULL(@FiltroTipo, '')), '');
        SET @FiltroMarca        = NULLIF(TRIM(ISNULL(@FiltroMarca, '')), '');
        SET @FiltroProveedor    = NULLIF(TRIM(ISNULL(@FiltroProveedor, '')), '');
        SET @FiltroDescuento    = NULLIF(TRIM(ISNULL(@FiltroDescuento, '')), '');

        SELECT
            PRD.PRD_RutaImagen  AS [Ruta Imagen],
            PRD.PRD_Descripcion AS [Descripción],
            TP.TIPO_PRD_Nombre AS [Tipo Producto],
            MP.MARC_PRD_Nombre AS [Marca],
            PER.PER_NombreCompleto  AS [Proveedor],
            ISNULL(D.DESC_NombreComercial, 'N/A') AS [Descuento Asignado], -- Nombre del descuento asignado al producto (independiente de si está vigente hoy)
            CASE -- Porcentaje del descuento asignado (independiente de si está vigente hoy)
                WHEN D.DESC_ID IS NOT NULL
                    THEN CONVERT(VARCHAR(6), D.DESC_DescuentoPct) + '%'
                ELSE
                    'N/A'
            END AS [Descuento %],
            CASE -- Indica si el descuento asignado está activo HOY
                WHEN D.DESC_ID IS NOT NULL
                    AND D.DESC_Estado = 1
                    AND @FechaHoy >= D.DESC_FechaInicio
                    AND @FechaHoy <= D.DESC_FechaFin
                    THEN 'Sí'
                WHEN D.DESC_ID IS NOT NULL
                    THEN 'No (Fuera de vigencia)'
                ELSE
                    'Sin descuento'
            END AS [Descuento Vigente Hoy],
            PRD.PRD_PrecioCompra AS [Precio Compra],
            PRD.PRD_PrecioVenta AS [Precio Venta],
            CASE -- Precio efectivo considerando si el descuento está vigente HOY
                WHEN D.DESC_ID IS NOT NULL
                    AND D.DESC_Estado = 1
                    AND @FechaHoy >= D.DESC_FechaInicio
                    AND @FechaHoy <= D.DESC_FechaFin
                    THEN CAST(
                            PRD.PRD_PrecioVenta - (PRD.PRD_PrecioVenta * D.DESC_DescuentoPct / 100.0)
                         AS DECIMAL(10,2))
                ELSE
                    PRD.PRD_PrecioVenta
            END AS [Precio Con Descuento],
            CASE
                WHEN PRD.PRD_Estado = 1
                    THEN 'Activo'
                ELSE
                    'Inactivo'
            END AS [Estado]
        FROM DBO.PRODUCTOS_TB PRD
        INNER JOIN DBO.TIPOS_PRODUCTOS_TB TP
            ON PRD.PRD_TIPO_PRD_ID = TP.TIPO_PRD_ID
        INNER JOIN DBO.MARCAS_PRODUCTOS_TB MP
            ON PRD.PRD_MARC_PRD_ID = MP.MARC_PRD_ID
        INNER JOIN DBO.PROVEEDORES_TB PRV
            ON PRD.PRD_PRV_ID = PRV.PRV_ID
        INNER JOIN DBO.PERSONAS_TB PER
            ON PRV.PRV_PER_ID = PER.PER_ID
        LEFT JOIN DBO.DESCUENTOS_TB D
            ON PRD.PRD_DESC_ID = D.DESC_ID
        WHERE
            -- Filtro por descripción: búsqueda parcial (LIKE)
            (@FiltroDescripcion IS NULL
                OR PRD.PRD_Descripcion LIKE '%' + @FiltroDescripcion + '%')
            -- Filtro por tipo de producto: nombre exacto
            AND (@FiltroTipo IS NULL
                OR TP.TIPO_PRD_Nombre = @FiltroTipo)
            -- Filtro por marca: nombre exacto
            AND (@FiltroMarca IS NULL
                OR MP.MARC_PRD_Nombre = @FiltroMarca)
            -- Filtro por proveedor: nombre exacto
            AND (@FiltroProveedor IS NULL
                OR PER.PER_NombreCompleto = @FiltroProveedor)
            -- Filtro por nombre de descuento: nombre exacto
            AND (@FiltroDescuento IS NULL
                OR D.DESC_NombreComercial = @FiltroDescuento)
        ORDER BY
            TP.TIPO_PRD_Nombre,
            MP.MARC_PRD_Nombre,
            PRD.PRD_Descripcion;

        -- Auditoría
        BEGIN TRY
            DECLARE @Descripcion VARCHAR(250);
            SET @Descripcion = 'Se usó CONSULTAR_PRODUCTOS_SP';

            -- Construir descripción con los filtros activos
            IF @FiltroDescripcion IS NOT NULL
                SET @Descripcion = @Descripcion + ' | Desc: ' + LEFT(@FiltroDescripcion, 20);
            IF @FiltroTipo IS NOT NULL
                SET @Descripcion = @Descripcion + ' | Tipo: ' + LEFT(@FiltroTipo, 20);
            IF @FiltroMarca IS NOT NULL
                SET @Descripcion = @Descripcion + ' | Marca: ' + LEFT(@FiltroMarca, 20);
            IF @FiltroProveedor IS NOT NULL
                SET @Descripcion = @Descripcion + ' | Prov: ' + LEFT(@FiltroProveedor, 20);
            IF @FiltroDescuento IS NOT NULL
                SET @Descripcion = @Descripcion + ' | Desc.Com: ' + LEFT(@FiltroDescuento, 20);

            IF @FiltroDescripcion IS NULL
                AND @FiltroTipo IS NULL
                AND @FiltroMarca IS NULL
                AND @FiltroProveedor IS NULL
                AND @FiltroDescuento IS NULL
                SET @Descripcion = @Descripcion + ' sin filtros (Todos).';
            ELSE
                SET @Descripcion = LEFT(@Descripcion, 247) + '.';

            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID     = @Persona_ID,
                @Accion         = 'SELECT',
                @TablaAfectada  = 'PRODUCTOS_TB',
                @FilaAfectada   = 0,
                @Descripcion    = @Descripcion,
                @Antes          = NULL,
                @Despues        = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();
        DECLARE @ErrorSeverity  INT             = ERROR_SEVERITY();
        DECLARE @ErrorState     INT             = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_PRODUCTO_SP
    @NombreUsuario          VARCHAR(75),
    @Descripcion            VARCHAR(150),           -- Identificador del producto a modificar
    @NuevoRutaImagen        VARCHAR(275) = NULL,
    @NuevaDescripcion       VARCHAR(150) = NULL,
    @NuevoTipoProducto      VARCHAR(75)  = NULL,    -- Nombre del tipo de producto
    @NuevaMarca             VARCHAR(75)  = NULL,    -- Nombre de la marca
    @NuevoProveedor         VARCHAR(150) = NULL,    -- Nombre completo del proveedor
    @NuevoDescuento         VARCHAR(100) = NULL,    -- Nombre comercial del descuento, '' = quitar descuento
    @NuevoPrecioCompra      DECIMAL(10,2)= NULL,
    @NuevoPrecioVenta       DECIMAL(10,2)= NULL,
    @NuevoEstado            BIT          = NULL,
    -- Inventario
    @NombreUbicacion        VARCHAR(75)  = NULL,    -- Ubicación a modificar 
    @NuevoStockMinimo       INT          = NULL,    -- NULL = no modificar
    @AjusteStock            INT          = NULL     -- Positivo = suma, Negativo = resta, NULL = no tocar
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID     INT;
    DECLARE @PRD_ID         INT;
    DECLARE @TIPO_PRD_ID    INT;
    DECLARE @MARC_PRD_ID    INT;
    DECLARE @PRV_ID         INT;
    DECLARE @DESC_ID        INT;
    DECLARE @UBI_INV_ID     INT;
    DECLARE @INV_ID         INT;
    DECLARE @StockActual    INT;
    DECLARE @FechaHoy       DATE = CAST(GETDATE() AS DATE);
    DECLARE @QuitarDescuento BIT = 0;

    -- Normalización
    SET @Descripcion        = TRIM(ISNULL(@Descripcion, ''));
    SET @NuevoRutaImagen    = NULLIF(TRIM(ISNULL(@NuevoRutaImagen, '')), '');
    SET @NuevaDescripcion   = NULLIF(TRIM(ISNULL(@NuevaDescripcion, '')), '');
    SET @NuevoTipoProducto  = NULLIF(TRIM(ISNULL(@NuevoTipoProducto, '')), '');
    SET @NuevaMarca         = NULLIF(TRIM(ISNULL(@NuevaMarca, '')), '');
    SET @NuevoProveedor     = NULLIF(TRIM(ISNULL(@NuevoProveedor, '')), '');
    SET @NombreUbicacion    = NULLIF(TRIM(ISNULL(@NombreUbicacion, '')), '');

    DECLARE @DescuentoInput VARCHAR(100) = @NuevoDescuento;  -- Preservar original
    SET @NuevoDescuento = NULLIF(TRIM(ISNULL(@NuevoDescuento, '')), '');

    -- Descuento: '' = quitar, NULL = no tocar, texto = cambiar
    IF @DescuentoInput IS NOT NULL AND TRIM(@DescuentoInput) = ''
        SET @QuitarDescuento = 1;
    ELSE
        SET @QuitarDescuento = 0;

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Validación de permisos
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1
            AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Obtener el producto a modificar
        IF LEN(@Descripcion) = 0
        BEGIN
            RAISERROR('Error: La descripción del producto no puede estar vacía.', 16, 1);
            RETURN;
        END;

        SELECT @PRD_ID = PRD_ID
        FROM DBO.PRODUCTOS_TB
        WHERE PRD_Descripcion = @Descripcion;

        IF @PRD_ID IS NULL
        BEGIN
            RAISERROR('Error: El producto [%s] no existe.', 16, 1, @Descripcion);
            RETURN;
        END;

        -- Verificar que se especificó al menos un cambio
        IF @NuevoRutaImagen IS NULL
            AND @NuevaDescripcion IS NULL
            AND @NuevoTipoProducto IS NULL
            AND @NuevaMarca IS NULL
            AND @NuevoProveedor IS NULL
            AND @NuevoDescuento IS NULL
            AND @QuitarDescuento = 0
            AND @NuevoPrecioCompra IS NULL
            AND @NuevoPrecioVenta IS NULL
            AND @NuevoEstado IS NULL
            AND @NuevoStockMinimo IS NULL
            AND @AjusteStock IS NULL
        BEGIN
            RAISERROR('No se especificaron cambios para el producto [%s].', 16, 1, @Descripcion);
            RETURN;
        END;

        -- Validar que cambios de inventario tengan ubicación
        IF (@NuevoStockMinimo IS NOT NULL OR @AjusteStock IS NOT NULL)
            AND @NombreUbicacion IS NULL
        BEGIN
            RAISERROR('Error: Debe especificar la ubicación para modificar el inventario.', 16, 1);
            RETURN;
        END;

        -- Foreign Keys
        -- Tipo de producto
        IF @NuevoTipoProducto IS NOT NULL
        BEGIN
            SELECT @TIPO_PRD_ID = TIPO_PRD_ID
            FROM DBO.TIPOS_PRODUCTOS_TB
            WHERE TIPO_PRD_Nombre = @NuevoTipoProducto
                AND TIPO_PRD_Estado = 1;

            IF @TIPO_PRD_ID IS NULL
            BEGIN
                RAISERROR('Error: El tipo de producto [%s] no existe o está inactivo.', 16, 1, @NuevoTipoProducto);
                RETURN;
            END;
        END;

        -- Marca
        IF @NuevaMarca IS NOT NULL
        BEGIN
            SELECT @MARC_PRD_ID = MARC_PRD_ID
            FROM DBO.MARCAS_PRODUCTOS_TB
            WHERE MARC_PRD_Nombre = @NuevaMarca
                AND MARC_PRD_Estado = 1;

            IF @MARC_PRD_ID IS NULL
            BEGIN
                RAISERROR('Error: La marca [%s] no existe o está inactiva.', 16, 1, @NuevaMarca);
                RETURN;
            END;
        END;

        -- Proveedor
        IF @NuevoProveedor IS NOT NULL
        BEGIN
            SELECT @PRV_ID = PRV.PRV_ID
            FROM DBO.PROVEEDORES_TB PRV
            INNER JOIN DBO.PERSONAS_TB P
                ON PRV.PRV_PER_ID = P.PER_ID
            WHERE P.PER_NombreCompleto = @NuevoProveedor
                AND PRV.PRV_Estado = 1
                AND P.PER_Estado   = 1;

            IF @PRV_ID IS NULL
            BEGIN
                RAISERROR('Error: El proveedor [%s] no existe o está inactivo.', 16, 1, @NuevoProveedor);
                RETURN;
            END;
        END;

        -- Descuento nuevo
        IF @NuevoDescuento IS NOT NULL
        BEGIN
            SELECT @DESC_ID = DESC_ID
            FROM DBO.DESCUENTOS_TB
            WHERE DESC_NombreComercial = @NuevoDescuento
                AND DESC_Estado = 1
                AND @FechaHoy <= DESC_FechaFin;

            IF @DESC_ID IS NULL
            BEGIN
                RAISERROR('Error: El descuento [%s] no existe, está inactivo o no está vigente.', 16, 1, @NuevoDescuento);
                RETURN;
            END;
        END;

        -- Validación de precios
        IF @NuevoPrecioCompra IS NOT NULL AND @NuevoPrecioCompra < 0
        BEGIN
            RAISERROR('Error: El precio de compra no puede ser negativo.', 16, 1);
            RETURN;
        END;

        IF @NuevoPrecioVenta IS NOT NULL AND @NuevoPrecioVenta <= 0
        BEGIN
            RAISERROR('Error: El precio de venta debe ser mayor a 0.', 16, 1);
            RETURN;
        END;

        -- Validar precios considerando valores actuales
        IF @NuevoPrecioCompra IS NOT NULL OR @NuevoPrecioVenta IS NOT NULL
        BEGIN
            DECLARE @PrecioCompraFinal DECIMAL(10,2);
            DECLARE @PrecioVentaFinal  DECIMAL(10,2);

            SELECT
                @PrecioCompraFinal = ISNULL(@NuevoPrecioCompra, PRD_PrecioCompra),
                @PrecioVentaFinal  = ISNULL(@NuevoPrecioVenta,  PRD_PrecioVenta)
            FROM DBO.PRODUCTOS_TB
            WHERE PRD_ID = @PRD_ID;

            IF @PrecioVentaFinal < @PrecioCompraFinal
            BEGIN
                RAISERROR('Error: El precio de venta no puede ser menor al precio de compra.', 16, 1);
                RETURN;
            END;
        END;
        
        -- Validaciones de inventario
        IF @NombreUbicacion IS NOT NULL
        BEGIN
            SELECT  
                @UBI_INV_ID  = U.UBI_INV_ID,
                @INV_ID      = I.INV_ID,
                @StockActual = I.INV_StockActual
            FROM DBO.UBI_INVENTARIOS_TB U
            LEFT JOIN DBO.INVENTARIOS_TB I
                ON U.UBI_INV_ID    = I.INV_UBI_INV_ID
                AND I.INV_PRD_ID   = @PRD_ID
            WHERE U.UBI_INV_Nombre = @NombreUbicacion
                AND U.UBI_INV_Estado = 1;

            IF @UBI_INV_ID IS NULL
            BEGIN
                RAISERROR('Error: La ubicación [%s] no existe o está inactiva.', 16, 1, @NombreUbicacion);
                RETURN;
            END;

            IF @INV_ID IS NULL
            BEGIN
                RAISERROR('Error: El producto [%s] no está registrado en la ubicación [%s].', 16, 1, @Descripcion, @NombreUbicacion);
                RETURN;
            END;
        END;

        IF @NuevoStockMinimo IS NOT NULL AND @NuevoStockMinimo < 0
        BEGIN
            RAISERROR('Error: El stock mínimo no puede ser negativo.', 16, 1);
            RETURN;
        END;

        IF @AjusteStock IS NOT NULL AND @AjusteStock = 0
        BEGIN
            RAISERROR('Error: El ajuste de stock no puede ser 0.', 16, 1);
            RETURN;
        END;

        -- Validar que la resta no deje stock negativo
        IF @AjusteStock IS NOT NULL AND @AjusteStock < 0
        BEGIN
            IF (@StockActual + @AjusteStock) < 0
            BEGIN
                RAISERROR('Error: No tenemos esa cantidad de stock en la ubicación ingresada. Stock actual: %d, Ajuste: %d.', 16, 1, @StockActual, @AjusteStock);
                RETURN;
            END;
        END;
        
        -- Update
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'MODIFICAR_PRODUCTO_SP';

        -- Update producto
        UPDATE DBO.PRODUCTOS_TB
        SET
            PRD_RutaImagen  = ISNULL(@NuevoRutaImagen,  PRD_RutaImagen),
            PRD_Descripcion = ISNULL(@NuevaDescripcion, PRD_Descripcion),
            PRD_TIPO_PRD_ID = ISNULL(@TIPO_PRD_ID,      PRD_TIPO_PRD_ID),
            PRD_MARC_PRD_ID = ISNULL(@MARC_PRD_ID,      PRD_MARC_PRD_ID),
            PRD_PRV_ID      = ISNULL(@PRV_ID,           PRD_PRV_ID),
            PRD_DESC_ID     = CASE
                                  WHEN @QuitarDescuento = 1 THEN NULL
                                  WHEN @DESC_ID IS NOT NULL THEN @DESC_ID
                                  ELSE PRD_DESC_ID
                              END,
            PRD_PrecioCompra = ISNULL(@NuevoPrecioCompra, PRD_PrecioCompra),
            PRD_PrecioVenta  = ISNULL(@NuevoPrecioVenta,  PRD_PrecioVenta),
            PRD_Estado       = ISNULL(@NuevoEstado,       PRD_Estado)
        WHERE PRD_ID = @PRD_ID;

        -- Update inventario (solo si se indicó ubicación y hay algo que cambiar)
        IF @INV_ID IS NOT NULL AND (@NuevoStockMinimo IS NOT NULL OR @AjusteStock IS NOT NULL)
        BEGIN
            UPDATE DBO.INVENTARIOS_TB
            SET
                INV_StockMinimo = ISNULL(@NuevoStockMinimo, INV_StockMinimo),
                INV_StockActual = CASE
                                      WHEN @AjusteStock IS NOT NULL 
                                        THEN INV_StockActual + @AjusteStock
                                      ELSE 
                                        INV_StockActual
                                  END
            WHERE INV_ID = @INV_ID;
        END;

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0 ROLLBACK;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        DECLARE @ErrorMessage  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT            = ERROR_SEVERITY();
        DECLARE @ErrorState    INT            = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_INVENTARIO_SP
    @NombreUsuario      VARCHAR(75),
    @FiltroUbicacion    VARCHAR(75)  = NULL, -- NULL = todas las ubicaciones
    @FiltroProducto     VARCHAR(150) = NULL  -- NULL = todos los productos (LIKE)
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID  INT;
    DECLARE @Descripcion VARCHAR(250);

    SET @FiltroUbicacion = NULLIF(TRIM(ISNULL(@FiltroUbicacion, '')), '');
    SET @FiltroProducto  = NULLIF(TRIM(ISNULL(@FiltroProducto,  '')), '');

    BEGIN TRY

        -- Validación de usuario activo
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Validar que la ubicación existe si se especificó
        IF @FiltroUbicacion IS NOT NULL
            AND NOT EXISTS (
                SELECT 1
                FROM DBO.UBI_INVENTARIOS_TB
                WHERE UBI_INV_Nombre = @FiltroUbicacion
            )
        BEGIN
            RAISERROR('Error: La ubicación [%s] no existe.', 16, 1, @FiltroUbicacion);
            RETURN;
        END;

        SELECT
            U.UBI_INV_Nombre AS [Ubicación],
            P.PRD_Descripcion AS [Producto],
            I.INV_StockActual AS [Stock Actual],
            I.INV_StockMinimo AS [Stock Mínimo],
            CASE
                WHEN I.INV_StockActual = 0 
                    THEN 'Sin stock'
                WHEN I.INV_StockActual <= I.INV_StockMinimo 
                    THEN 'Stock bajo'
                ELSE
                    'OK'
            END AS [Alerta],
            CASE
                WHEN I.INV_Estado = 1 
                    THEN 'Activo'
                ELSE 
                    'Inactivo'
            END AS [Estado]
        FROM DBO.INVENTARIOS_TB I
        INNER JOIN DBO.UBI_INVENTARIOS_TB U
            ON I.INV_UBI_INV_ID = U.UBI_INV_ID
        INNER JOIN DBO.PRODUCTOS_TB P
            ON I.INV_PRD_ID = P.PRD_ID
        WHERE
            (@FiltroUbicacion IS NULL OR U.UBI_INV_Nombre = @FiltroUbicacion)
            AND (@FiltroProducto  IS NULL OR P.PRD_Descripcion LIKE '%' + @FiltroProducto + '%')
        ORDER BY -- Alertas críticas primero, luego por ubicación y producto
            CASE
                WHEN I.INV_StockActual = 0 
                    THEN 0
                WHEN I.INV_StockActual <= I.INV_StockMinimo 
                    THEN 1
                ELSE 
                    2
            END,
            U.UBI_INV_Nombre,
            P.PRD_Descripcion;

        -- Auditoría
        BEGIN TRY
            SET @Descripcion = 'Se usó CONSULTAR_INVENTARIO_SP';

            IF @FiltroUbicacion IS NOT NULL
                SET @Descripcion = @Descripcion + ', con filtro de ubicación: [' + @FiltroUbicacion + ']';

            IF @FiltroProducto IS NOT NULL
                SET @Descripcion = @Descripcion + ', con filtro de producto: [' + LEFT(@FiltroProducto, 30) + ']';

            IF @FiltroUbicacion IS NULL AND @FiltroProducto IS NULL
                SET @Descripcion = @Descripcion + ' sin filtro específico (Todos).';
            ELSE
                SET @Descripcion = LEFT(@Descripcion, 247) + '.';

            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID    = @Persona_ID,
                @Accion        = 'SELECT',
                @TablaAfectada = 'INVENTARIOS_TB',
                @FilaAfectada  = 0,
                @Descripcion   = @Descripcion,
                @Antes         = NULL,
                @Despues       = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT            = ERROR_SEVERITY();
        DECLARE @ErrorState    INT            = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.FACTURAR_CLIENTE_SP
    @NombreUsuario          VARCHAR(75),
    @IdentificacionCliente  VARCHAR(50),
    @ProductosJSON          NVARCHAR(MAX),          -- [{"PRD_Descripcion":"...","TipoProducto":"...","Marca":"...","Proveedor":"...","Cantidad":N}, ...]
    @DireccionEntrega       VARCHAR(150)  = NULL,
    @ObservacionesEntrega   VARCHAR(150)  = NULL,
    @DiasEntrega            INT           = 3,
    @CostoPorDiaEnvio       DECIMAL(10,2) = 750.00
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    -- =========================================================================
    -- VARIABLES
    -- =========================================================================
    DECLARE @Persona_ID_Ejecutor    INT;
    DECLARE @RolEjecutor            VARCHAR(50);
    DECLARE @NombreEjecutor         VARCHAR(150);
    DECLARE @Cliente_ID             INT;
    DECLARE @NombreCliente          VARCHAR(150);
    DECLARE @TIPO_PER_ID_Cliente    INT;
    DECLARE @DescuentoPctCliente    DECIMAL(5,2);
    DECLARE @MontoMetaActual        DECIMAL(10,2);
    DECLARE @NombreTipoAnterior     VARCHAR(50);

    DECLARE @ENC_FAC_ID             INT;
    DECLARE @NumeroFactura          VARCHAR(75);
    DECLARE @FechaHoy               DATE = CAST(SYSDATETIME() AS DATE);

    DECLARE @Subtotal               DECIMAL(19,4) = 0.0000;
    DECLARE @DescuentoTotal         DECIMAL(19,4) = 0.0000;
    DECLARE @ImpuestoPct            DECIMAL(5,2)  = 13.00;
    DECLARE @ImpuestoTotal          DECIMAL(19,4) = 0.0000;
    DECLARE @CostoEnvio             DECIMAL(19,4) = 0.0000;
    DECLARE @Total                  DECIMAL(19,4) = 0.0000;

    DECLARE @EsEntrega              BIT = 0;
    DECLARE @FechaEntrega           DATE;
    DECLARE @EST_ENT_ID_Sucursal    INT;

    DECLARE @NuevoTipo_PER_ID       INT;
    DECLARE @NombreTipoNuevo        VARCHAR(50);
    DECLARE @MontoAcumulado         DECIMAL(10,2);
    DECLARE @DESC_ID_Neutro         INT;

    -- Tabla de salida para capturar el ID generado por el INSERT (reemplaza SCOPE_IDENTITY)
    DECLARE @InsertedFactura        TABLE (ENC_FAC_ID INT);

    -- =========================================================================
    -- BLOQUE 1 — Validaciones de parámetros (sin transacción, sin TRY anidado)
    -- =========================================================================
    SET @IdentificacionCliente = TRIM(ISNULL(@IdentificacionCliente, ''));
    SET @DireccionEntrega      = NULLIF(TRIM(ISNULL(@DireccionEntrega, '')), '');
    SET @ObservacionesEntrega  = NULLIF(TRIM(ISNULL(@ObservacionesEntrega, '')), '');

    IF @DiasEntrega < 0
        THROW 50001, N'Error: Los días de entrega no pueden ser negativos.', 1;

    IF @CostoPorDiaEnvio < 0
        THROW 50001, N'Error: El costo por día de envío no puede ser negativo.', 1;

    IF LEN(@IdentificacionCliente) = 0
        THROW 50001, N'Error: La identificación del cliente no puede estar vacía.', 1;

    IF @ProductosJSON IS NULL OR LEN(TRIM(@ProductosJSON)) = 0
        THROW 50001, N'Error: Debe especificar al menos un producto.', 1;

    -- =========================================================================
    -- BLOQUE 2 — Parseo y validación del JSON (sin transacción)
    -- El TRY anidado aquí es seguro porque no hay transacción activa todavía.
    -- =========================================================================
    CREATE TABLE #ProductosFactura (
        PRD_Descripcion VARCHAR(150),
        TipoProducto    VARCHAR(75),
        Marca           VARCHAR(75),
        Proveedor       VARCHAR(150),
        Cantidad        INT,
        PRIMARY KEY (PRD_Descripcion, TipoProducto, Marca, Proveedor)
    );

    BEGIN TRY
        -- OPENJSON con schema explícito: más eficiente y legible que JSON_VALUE por columna
        INSERT INTO #ProductosFactura (PRD_Descripcion, TipoProducto, Marca, Proveedor, Cantidad)
        SELECT
            TRIM(j.PRD_Descripcion),
            TRIM(j.TipoProducto),
            TRIM(j.Marca),
            TRIM(j.Proveedor),
            TRY_CAST(j.Cantidad AS INT)         -- TRY_CAST: NULL si el valor no es numérico
        FROM OPENJSON(@ProductosJSON) WITH (
            PRD_Descripcion NVARCHAR(150) '$.PRD_Descripcion',
            TipoProducto    NVARCHAR(75)  '$.TipoProducto',
            Marca           NVARCHAR(75)  '$.Marca',
            Proveedor       NVARCHAR(150) '$.Proveedor',
            Cantidad        NVARCHAR(20)  '$.Cantidad'   -- como string para TRY_CAST seguro
        ) AS j;
    END TRY
    BEGIN CATCH
        DROP TABLE IF EXISTS #ProductosFactura;
        THROW 50001, N'Error: El formato del JSON de productos no es válido.', 1;
    END CATCH;

    IF NOT EXISTS (SELECT 1 FROM #ProductosFactura)
    BEGIN
        DROP TABLE IF EXISTS #ProductosFactura;
        THROW 50001, N'Error: El JSON de productos no contiene ningún ítem válido.', 1;
    END;

    IF EXISTS (SELECT 1 FROM #ProductosFactura WHERE Cantidad IS NULL OR Cantidad <= 0)
    BEGIN
        DROP TABLE IF EXISTS #ProductosFactura;
        THROW 50001, N'Error: Todos los productos deben tener una cantidad mayor a 0.', 1;
    END;

    IF EXISTS (
        SELECT 1 FROM #ProductosFactura
        WHERE ISNULL(PRD_Descripcion,'') = '' OR ISNULL(TipoProducto,'') = ''
           OR ISNULL(Marca,'')           = '' OR ISNULL(Proveedor,'')    = ''
    )
    BEGIN
        DROP TABLE IF EXISTS #ProductosFactura;
        THROW 50001, N'Error: Todos los productos deben tener Descripción, Tipo, Marca y Proveedor.', 1;
    END;

    -- =========================================================================
    -- BLOQUE 3 — Transacción principal (sin TRY anidados que escriban en BD)
    -- =========================================================================
    BEGIN TRY

        BEGIN TRANSACTION;

        -- 0. Validar descuento neutro
        SELECT TOP 1 @DESC_ID_Neutro = DESC_ID
        FROM DBO.DESCUENTOS_TB
        WHERE DESC_DescuentoPct = 0.00 AND DESC_Estado = 1
        ORDER BY DESC_ID;

        IF @DESC_ID_Neutro IS NULL
            THROW 50002, N'Error de Configuración: No existe un registro de descuento con 0% activo en DESCUENTOS_TB.', 1;

        -- 1. Validar ejecutor
        SELECT
            @Persona_ID_Ejecutor = S.SESION_PER_ID,
            @RolEjecutor         = R.ROL_Nombre,
            @NombreEjecutor      = P.PER_NombreCompleto
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R    ON S.SESION_ROL_ID = R.ROL_ID
        INNER JOIN DBO.PERSONAS_TB P ON S.SESION_PER_ID = P.PER_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
          AND S.SESION_Estado = 1
          AND R.ROL_Nombre IN ('Vendedor', 'Administrador', 'Cliente');

        IF @Persona_ID_Ejecutor IS NULL
        BEGIN
            DECLARE @msgEjecutor NVARCHAR(500) = CONCAT(N'Acceso denegado: El usuario [', @NombreUsuario, N'] no tiene permisos para facturar.');
            THROW 50003, @msgEjecutor, 1;
        END;

        -- 2. Validar cliente
        SELECT
            @Cliente_ID             = P.PER_ID,
            @NombreCliente          = P.PER_NombreCompleto,
            @TIPO_PER_ID_Cliente    = P.PER_TIPO_PER_ID,
            @DescuentoPctCliente    = TP.TIPO_PER_DescuentoPct,
            @MontoMetaActual        = TP.TIPO_PER_MontoMeta,
            @NombreTipoAnterior     = TP.TIPO_PER_Nombre
        FROM DBO.PERSONAS_TB P
        INNER JOIN DBO.TIPOS_PERSONAS_TB TP ON P.PER_TIPO_PER_ID = TP.TIPO_PER_ID
        WHERE P.PER_Identificacion = @IdentificacionCliente AND P.PER_Estado = 1;

        IF @Cliente_ID IS NULL
        BEGIN
            DECLARE @msgCliente NVARCHAR(500) = CONCAT(N'Error: No existe un cliente activo con la identificación [', @IdentificacionCliente, N'].');
            THROW 50001, @msgCliente, 1;
        END;

        IF @RolEjecutor = 'Cliente' AND @Persona_ID_Ejecutor != @Cliente_ID
            THROW 50003, N'Acceso denegado: Un cliente solo puede realizar compras a nombre propio.', 1;

        -- 3. Validar entrega
        IF @DireccionEntrega IS NOT NULL
        BEGIN
            SET @EsEntrega    = 1;
            SET @FechaEntrega = DATEADD(DAY, @DiasEntrega, @FechaHoy);
            SET @CostoEnvio   = CAST(@DiasEntrega * @CostoPorDiaEnvio AS DECIMAL(19,4));

            SELECT @EST_ENT_ID_Sucursal = EST_ENT_ID
            FROM DBO.ESTADOS_ENTREGAS_TB
            WHERE EST_ENT_Nombre = 'En Sucursal' AND EST_ENT_Estado = 1;

            IF @EST_ENT_ID_Sucursal IS NULL
                THROW 50002, N'Error: No se encontró el estado [En Sucursal] en ESTADOS_ENTREGAS_TB.', 1;
        END;

        -- 4. Resolver productos: ubicación automática por mayor stock disponible
        CREATE TABLE #LineasFactura (
            PRD_ID          INT,
            PRD_Descripcion VARCHAR(150),
            Cantidad        INT,
            PrecioUnitario  DECIMAL(10,2),
            DESC_ID         INT,
            DescuentoMonto  DECIMAL(10,2),
            SubtotalLinea   DECIMAL(10,2),
            TotalLinea      DECIMAL(10,2),
            UBI_INV_ID      INT,
            NombreUbicacion VARCHAR(75)
        );

        DECLARE @PRD_Desc           VARCHAR(150);
        DECLARE @PRD_Tipo           VARCHAR(75);
        DECLARE @PRD_Marca          VARCHAR(75);
        DECLARE @PRD_Proveedor      VARCHAR(150);
        DECLARE @PRD_Cant           INT;
        DECLARE @PRD_ID_Var         INT;
        DECLARE @PRD_Precio         DECIMAL(10,2);
        DECLARE @DESC_ID_PRD        INT;
        DECLARE @DESC_Pct_PRD       DECIMAL(5,2);
        DECLARE @DescPctTotal       DECIMAL(5,2);
        DECLARE @SubLinea           DECIMAL(19,4);
        DECLARE @TotalLinea_Var     DECIMAL(19,4);
        DECLARE @DescMonto          DECIMAL(19,4);
        DECLARE @UBI_INV_ID_Linea   INT;
        DECLARE @NombreUbi_Linea    VARCHAR(75);
        DECLARE @StockDisponible    INT;

        DECLARE cur_productos CURSOR LOCAL FAST_FORWARD FOR
            SELECT PRD_Descripcion, TipoProducto, Marca, Proveedor, Cantidad
            FROM #ProductosFactura;

        OPEN cur_productos;
        FETCH NEXT FROM cur_productos INTO @PRD_Desc, @PRD_Tipo, @PRD_Marca, @PRD_Proveedor, @PRD_Cant;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @PRD_ID_Var       = NULL;
            SET @UBI_INV_ID_Linea = NULL;

            -- Buscar producto + ubicación con stock suficiente (mayor stock primero)
            SELECT TOP 1
                @PRD_ID_Var       = PRD.PRD_ID,
                @PRD_Precio       = PRD.PRD_PrecioVenta,
                @DESC_ID_PRD      = PRD.PRD_DESC_ID,
                @UBI_INV_ID_Linea = INV.INV_UBI_INV_ID,
                @NombreUbi_Linea  = UBI.UBI_INV_Nombre,
                @StockDisponible  = INV.INV_StockActual
            FROM DBO.PRODUCTOS_TB PRD
            INNER JOIN DBO.TIPOS_PRODUCTOS_TB  TP  ON PRD.PRD_TIPO_PRD_ID = TP.TIPO_PRD_ID
            INNER JOIN DBO.MARCAS_PRODUCTOS_TB MP  ON PRD.PRD_MARC_PRD_ID = MP.MARC_PRD_ID
            INNER JOIN DBO.PROVEEDORES_TB       PRV ON PRD.PRD_PRV_ID      = PRV.PRV_ID
            INNER JOIN DBO.PERSONAS_TB          P   ON PRV.PRV_PER_ID      = P.PER_ID
            INNER JOIN DBO.INVENTARIOS_TB       INV ON PRD.PRD_ID          = INV.INV_PRD_ID
                                                    AND INV.INV_Estado      = 1
                                                    AND INV.INV_StockActual >= @PRD_Cant
            INNER JOIN DBO.UBI_INVENTARIOS_TB   UBI ON INV.INV_UBI_INV_ID  = UBI.UBI_INV_ID
                                                    AND UBI.UBI_INV_Estado  = 1
            WHERE PRD.PRD_Descripcion  = @PRD_Desc
              AND TP.TIPO_PRD_Nombre   = @PRD_Tipo
              AND MP.MARC_PRD_Nombre   = @PRD_Marca
              AND P.PER_NombreCompleto = @PRD_Proveedor
              AND PRD.PRD_Estado       = 1
            ORDER BY INV.INV_StockActual DESC, UBI.UBI_INV_Nombre ASC;

            -- Si no se encontró, distinguir: ¿no existe o no hay stock?
            IF @PRD_ID_Var IS NULL
            BEGIN
                DECLARE @ExistePRD INT;
                SELECT @ExistePRD = COUNT(*)
                FROM DBO.PRODUCTOS_TB PRD
                INNER JOIN DBO.TIPOS_PRODUCTOS_TB  TP  ON PRD.PRD_TIPO_PRD_ID = TP.TIPO_PRD_ID
                INNER JOIN DBO.MARCAS_PRODUCTOS_TB MP  ON PRD.PRD_MARC_PRD_ID = MP.MARC_PRD_ID
                INNER JOIN DBO.PROVEEDORES_TB       PRV ON PRD.PRD_PRV_ID     = PRV.PRV_ID
                INNER JOIN DBO.PERSONAS_TB          P   ON PRV.PRV_PER_ID     = P.PER_ID
                WHERE PRD.PRD_Descripcion  = @PRD_Desc
                  AND TP.TIPO_PRD_Nombre   = @PRD_Tipo
                  AND MP.MARC_PRD_Nombre   = @PRD_Marca
                  AND P.PER_NombreCompleto = @PRD_Proveedor
                  AND PRD.PRD_Estado       = 1;

                -- El CATCH maneja: cursor, temp tables, session context y re-throw
                DECLARE @msgProducto NVARCHAR(1000) =
                    CASE WHEN @ExistePRD = 0
                        THEN CONCAT(N'Error: El producto [', @PRD_Desc, N'] de tipo [', @PRD_Tipo,
                                    N'], marca [', @PRD_Marca, N'], proveedor [', @PRD_Proveedor,
                                    N'] no existe o está inactivo.')
                        ELSE CONCAT(N'Error: Stock insuficiente para [', @PRD_Desc,
                                    N']. Ninguna ubicación tiene las ',
                                    CAST(@PRD_Cant AS NVARCHAR(10)), N' unidades requeridas.')
                    END;
                THROW 50001, @msgProducto, 1;
            END;

            -- Descuento del producto vigente hoy
            SET @DESC_Pct_PRD = 0.00;
            IF @DESC_ID_PRD IS NOT NULL
            BEGIN
                SELECT @DESC_Pct_PRD = ISNULL(DESC_DescuentoPct, 0.00)
                FROM DBO.DESCUENTOS_TB
                WHERE DESC_ID = @DESC_ID_PRD AND DESC_Estado = 1
                  AND @FechaHoy >= DESC_FechaInicio AND @FechaHoy <= DESC_FechaFin;

                SET @DESC_Pct_PRD = ISNULL(@DESC_Pct_PRD, 0.00);
            END;

            SET @DescPctTotal   = @DESC_Pct_PRD + @DescuentoPctCliente;
            SET @SubLinea       = CAST(@PRD_Precio * @PRD_Cant AS DECIMAL(19,4));

            -- GREATEST (SQL 2022): piso en cero sin necesidad de IF auxiliar
            SET @TotalLinea_Var = GREATEST(
                CAST(0 AS DECIMAL(19,4)),
                CAST(@PRD_Precio * (1.0 - @DescPctTotal / 100.0) * @PRD_Cant AS DECIMAL(19,4))
            );

            SET @DescMonto = CAST(@SubLinea - @TotalLinea_Var AS DECIMAL(19,4));

            INSERT INTO #LineasFactura (
                PRD_ID, PRD_Descripcion, Cantidad, PrecioUnitario, DESC_ID,
                DescuentoMonto, SubtotalLinea, TotalLinea, UBI_INV_ID, NombreUbicacion
            )
            VALUES (
                @PRD_ID_Var, @PRD_Desc, @PRD_Cant, @PRD_Precio, @DESC_ID_PRD,
                CAST(@DescMonto AS DECIMAL(10,2)),
                CAST(@SubLinea AS DECIMAL(10,2)),
                CAST(@TotalLinea_Var AS DECIMAL(10,2)),
                @UBI_INV_ID_Linea, @NombreUbi_Linea
            );

            FETCH NEXT FROM cur_productos INTO @PRD_Desc, @PRD_Tipo, @PRD_Marca, @PRD_Proveedor, @PRD_Cant;
        END;

        CLOSE cur_productos;
        DEALLOCATE cur_productos;

        -- 5. Totales
        -- Los precios de venta YA incluyen IVA → se extrae, no se añade encima.
        -- IVA incluido = TotalNeto * 13/113  (inverso del factor 1.13)
        -- @Subtotal = suma bruta (para calcular descuento), luego se reemplaza por el neto.
        DECLARE @SubtotalBruto DECIMAL(19,4);
        SELECT
            @SubtotalBruto  = SUM(CAST(SubtotalLinea AS DECIMAL(19,4))),
            @DescuentoTotal = SUM(CAST(DescuentoMonto AS DECIMAL(19,4)))
        FROM #LineasFactura;

        -- Neto = suma de TotalLinea (precio final por línea, con descuento, IVA incluido)
        DECLARE @TotalNeto DECIMAL(19,4) = @SubtotalBruto - @DescuentoTotal;
        SET @ImpuestoTotal = CAST(@TotalNeto * @ImpuestoPct / (100.0 + @ImpuestoPct) AS DECIMAL(19,4));
        SET @Total         = @TotalNeto + @CostoEnvio;

        -- Subtotal almacenado = neto con descuento (IVA incluido), no el bruto.
        -- Así los campos del encabezado cuadran: Subtotal + Envío = Total
        SET @Subtotal = @TotalNeto;

        -- 6. Número de factura único: FAC-YYYYMMDD-XXXXX
        DECLARE @FechaParte     VARCHAR(8) = CONVERT(VARCHAR(8), SYSDATETIME(), 112);
        DECLARE @Consecutivo    INT;
        DECLARE @ConsecutivoStr VARCHAR(5);

        SELECT @Consecutivo = ISNULL(COUNT(*), 0) + 1
        FROM DBO.ENC_FACTURAS_TB WITH (UPDLOCK, HOLDLOCK)
        WHERE ENC_FAC_Numero LIKE 'FAC-' + @FechaParte + '-%';

        SET @ConsecutivoStr = RIGHT('00000' + CAST(@Consecutivo AS VARCHAR(5)), 5);
        SET @NumeroFactura  = 'FAC-' + @FechaParte + '-' + @ConsecutivoStr;

        WHILE EXISTS (SELECT 1 FROM DBO.ENC_FACTURAS_TB WHERE ENC_FAC_Numero = @NumeroFactura)
        BEGIN
            SET @Consecutivo    = @Consecutivo + 1;
            SET @ConsecutivoStr = RIGHT('00000' + CAST(@Consecutivo AS VARCHAR(5)), 5);
            SET @NumeroFactura  = 'FAC-' + @FechaParte + '-' + @ConsecutivoStr;
        END;

        -- 7. Insertar encabezado
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID_Ejecutor;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'FACTURAR_CLIENTE_SP';

        -- OUTPUT INTO reemplaza SCOPE_IDENTITY(): más seguro en escenarios con triggers
        INSERT INTO DBO.ENC_FACTURAS_TB (
            ENC_FAC_Numero, ENC_FAC_PER_ID,
            ENC_FAC_Subtotal, ENC_FAC_DescuentoTotal,
            ENC_FAC_ImpuestoPct, ENC_FAC_ImpuestoTotal,
            ENC_FAC_CostoEnvio, ENC_FAC_Total
        )
        OUTPUT INSERTED.ENC_FAC_ID INTO @InsertedFactura
        VALUES (
            @NumeroFactura, @Cliente_ID,
            CAST(@Subtotal AS DECIMAL(10,2)),      CAST(@DescuentoTotal AS DECIMAL(10,2)),
            @ImpuestoPct,                           CAST(@ImpuestoTotal AS DECIMAL(10,2)),
            CAST(@CostoEnvio AS DECIMAL(10,2)),     CAST(@Total AS DECIMAL(10,2))
        );

        SELECT @ENC_FAC_ID = ENC_FAC_ID FROM @InsertedFactura;

        -- 8. Insertar detalle
        INSERT INTO DBO.DET_FACTURAS_TB (
            DET_FAC_ENC_FAC_ID, DET_FAC_PRD_ID, DET_FAC_Cantidad,
            DET_FAC_PrecioUnitario, DET_FAC_DESC_ID,
            DET_FAC_DescuentoMonto, DET_FAC_SubtotalLinea, DET_FAC_TotalLinea
        )
        SELECT
            @ENC_FAC_ID, PRD_ID, Cantidad, PrecioUnitario,
            ISNULL(DESC_ID, @DESC_ID_Neutro),
            DescuentoMonto, SubtotalLinea, TotalLinea
        FROM #LineasFactura;

        -- 9. Descontar stock por ubicación de cada línea
        UPDATE I
        SET I.INV_StockActual = I.INV_StockActual - LF.Cantidad
        FROM DBO.INVENTARIOS_TB I
        INNER JOIN #LineasFactura LF
            ON I.INV_PRD_ID     = LF.PRD_ID
           AND I.INV_UBI_INV_ID = LF.UBI_INV_ID
        WHERE I.INV_Estado = 1;

        IF EXISTS (
            SELECT 1 FROM DBO.INVENTARIOS_TB I
            INNER JOIN #LineasFactura LF
                ON I.INV_PRD_ID = LF.PRD_ID AND I.INV_UBI_INV_ID = LF.UBI_INV_ID
            WHERE I.INV_StockActual < 0
        )
            THROW 50009, N'Error crítico: Stock negativo detectado post-actualización. Posible modificación concurrente.', 1;

        -- 10. Insertar entrega si aplica
        IF @EsEntrega = 1
        BEGIN
            INSERT INTO DBO.ENC_ENTREGAS_CLIENTES_TB (
                ENC_ENT_CLI_ENC_FAC_ID, ENC_ENT_CLI_FechaEntrega,
                ENC_ENT_CLI_DireccionEntrega, ENC_ENT_CLI_Observaciones,
                ENC_ENT_CLI_EST_ENT_ID
            )
            VALUES (
                @ENC_FAC_ID, @FechaEntrega,
                @DireccionEntrega, @ObservacionesEntrega,
                @EST_ENT_ID_Sucursal
            );
        END;

        -- 11. Upgrade de categoría
        SELECT @MontoAcumulado = ISNULL(SUM(ENC_FAC_Total), 0.00)
        FROM DBO.ENC_FACTURAS_TB
        WHERE ENC_FAC_PER_ID = @Cliente_ID;

        SELECT TOP 1
            @NuevoTipo_PER_ID = TIPO_PER_ID,
            @NombreTipoNuevo  = TIPO_PER_Nombre
        FROM DBO.TIPOS_PERSONAS_TB
        WHERE TIPO_PER_Nombre   LIKE 'Cliente%'
          AND TIPO_PER_Estado    = 1
          AND TIPO_PER_MontoMeta > @MontoMetaActual
          AND @MontoAcumulado   >= TIPO_PER_MontoMeta
        ORDER BY TIPO_PER_MontoMeta ASC;

        IF @NuevoTipo_PER_ID IS NOT NULL
            UPDATE DBO.PERSONAS_TB SET PER_TIPO_PER_ID = @NuevoTipo_PER_ID WHERE PER_ID = @Cliente_ID;
        ELSE
            SET @NombreTipoNuevo = @NombreTipoAnterior;

        COMMIT;  -- Transacción cerrada antes de cualquier TRY anidado

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        -- 12. Auditoría — DESPUÉS del COMMIT: sin transacción activa,
        --     XACT_ABORT no puede doomear nada. Fallo silencioso.
        DECLARE @UbicacionesUsadas VARCHAR(200);

        -- STRING_AGG reemplaza STUFF/FOR XML PATH: más legible y eficiente (SQL 2017+)
        SELECT @UbicacionesUsadas =
            (SELECT STRING_AGG(NombreUbicacion, ', ') WITHIN GROUP (ORDER BY NombreUbicacion)
             FROM (SELECT DISTINCT NombreUbicacion FROM #LineasFactura) AS T);

        DECLARE @DescAuditoria VARCHAR(250);
        SET @DescAuditoria =
            'Factura [' + @NumeroFactura + '] emitida a [' + LEFT(@NombreCliente, 35) + ']. ' +
            'Total: ' + CONVERT(VARCHAR(15), CAST(@Total AS DECIMAL(10,2))) + '. ' +
            'Items: ' + CAST((SELECT COUNT(*) FROM #LineasFactura) AS VARCHAR(5)) + '. ' +
            'Ubicaciones: ' + LEFT(ISNULL(@UbicacionesUsadas, 'N/A'), 50) + '.';

        BEGIN TRY
            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID    = @Persona_ID_Ejecutor,
                @Accion        = 'INSERT',
                @TablaAfectada = 'ENC_FACTURAS_TB',
                @FilaAfectada  = @ENC_FAC_ID,
                @Descripcion   = @DescAuditoria,
                @Antes         = NULL,
                @Despues       = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no revierte la factura ya confirmada
        END CATCH;

        -- 13. Respuesta: encabezado
        SELECT
            EF.ENC_FAC_Numero                                                    AS [Número Factura],
            FORMAT(EF.ENC_FAC_FechaHora, 'yyyy-MM-dd HH:mm:ss')                 AS [Fecha y Hora],
            (SELECT STRING_AGG(NombreUbicacion, ', ') WITHIN GROUP (ORDER BY NombreUbicacion)
             FROM (SELECT DISTINCT NombreUbicacion FROM #LineasFactura) AS T)    AS [Sucursales],
            CLI.PER_NombreCompleto                                               AS [Cliente],
            CLI.PER_Identificacion                                               AS [Identificación],
            TP_CLI.TIPO_PER_Nombre                                               AS [Tipo Cliente],
            CASE
                WHEN @Persona_ID_Ejecutor = @Cliente_ID THEN 'Auto-compra'
                ELSE @NombreEjecutor + ' (' + @RolEjecutor + ')'
            END                                                                  AS [Atendido por],
            EF.ENC_FAC_Subtotal                                                  AS [Subtotal],
            EF.ENC_FAC_DescuentoTotal                                            AS [Descuento Total],
            EF.ENC_FAC_ImpuestoPct                                               AS [IVA %],
            EF.ENC_FAC_ImpuestoTotal                                             AS [IVA],
            EF.ENC_FAC_CostoEnvio                                                AS [Costo Envío],
            EF.ENC_FAC_Total                                                     AS [Total],
            CASE WHEN ENT.ENC_ENT_CLI_ID IS NOT NULL THEN 'Sí' ELSE 'No' END    AS [Con Entrega],
            FORMAT(ENT.ENC_ENT_CLI_FechaEntrega, 'yyyy-MM-dd')                  AS [Fecha Entrega],
            ENT.ENC_ENT_CLI_DireccionEntrega                                     AS [Dirección Entrega],
            ENT.ENC_ENT_CLI_Observaciones                                        AS [Observaciones],
            EE.EST_ENT_Nombre                                                    AS [Estado Entrega],
            @NombreTipoAnterior                                                  AS [Categoría Anterior],
            @NombreTipoNuevo                                                     AS [Categoría Actual],
            CASE WHEN @NuevoTipo_PER_ID IS NOT NULL THEN '¡Subió de categoría!' ELSE 'Sin cambio' END AS [Upgrade]
        FROM DBO.ENC_FACTURAS_TB EF
        INNER JOIN DBO.PERSONAS_TB CLI              ON EF.ENC_FAC_PER_ID           = CLI.PER_ID
        INNER JOIN DBO.TIPOS_PERSONAS_TB TP_CLI     ON CLI.PER_TIPO_PER_ID          = TP_CLI.TIPO_PER_ID
        LEFT  JOIN DBO.ENC_ENTREGAS_CLIENTES_TB ENT ON EF.ENC_FAC_ID               = ENT.ENC_ENT_CLI_ENC_FAC_ID
        LEFT  JOIN DBO.ESTADOS_ENTREGAS_TB EE       ON ENT.ENC_ENT_CLI_EST_ENT_ID  = EE.EST_ENT_ID
        WHERE EF.ENC_FAC_ID = @ENC_FAC_ID;

        -- 14. Respuesta: detalle de líneas (incluye ubicación usada por producto)
        SELECT
            LF.NombreUbicacion                               AS [Ubicación],
            DF.DET_FAC_Cantidad                              AS [Cantidad],
            PRD.PRD_Descripcion                              AS [Producto],
            TP.TIPO_PRD_Nombre                               AS [Tipo],
            MP.MARC_PRD_Nombre                               AS [Marca],
            DF.DET_FAC_PrecioUnitario                        AS [Precio Unitario],
            ISNULL(D.DESC_NombreComercial, 'Sin descuento')  AS [Descuento Producto],
            @DescuentoPctCliente                             AS [Descuento Cliente %],
            DF.DET_FAC_DescuentoMonto                        AS [Monto Descuento],
            DF.DET_FAC_SubtotalLinea                         AS [Subtotal Línea],
            DF.DET_FAC_TotalLinea                            AS [Total Línea]
        FROM DBO.DET_FACTURAS_TB DF
        INNER JOIN DBO.PRODUCTOS_TB PRD      ON DF.DET_FAC_PRD_ID    = PRD.PRD_ID
        INNER JOIN DBO.TIPOS_PRODUCTOS_TB TP  ON PRD.PRD_TIPO_PRD_ID  = TP.TIPO_PRD_ID
        INNER JOIN DBO.MARCAS_PRODUCTOS_TB MP ON PRD.PRD_MARC_PRD_ID  = MP.MARC_PRD_ID
        INNER JOIN #LineasFactura LF          ON DF.DET_FAC_PRD_ID    = LF.PRD_ID
        LEFT  JOIN DBO.DESCUENTOS_TB D        ON DF.DET_FAC_DESC_ID   = D.DESC_ID
                                              AND D.DESC_DescuentoPct > 0
        WHERE DF.DET_FAC_ENC_FAC_ID = @ENC_FAC_ID
        ORDER BY LF.NombreUbicacion, PRD.PRD_Descripcion;

        DROP TABLE IF EXISTS #ProductosFactura;
        DROP TABLE IF EXISTS #LineasFactura;

    END TRY
    BEGIN CATCH

        -- XACT_STATE() = -1: transacción doomed, solo se puede hacer rollback
        -- XACT_STATE() =  1: transacción activa, se puede rollback
        -- XACT_STATE() =  0: sin transacción activa
        IF XACT_STATE() <> 0 ROLLBACK;

        IF CURSOR_STATUS('local', 'cur_productos') >= 0
        BEGIN CLOSE cur_productos; DEALLOCATE cur_productos; END;

        DROP TABLE IF EXISTS #ProductosFactura;
        DROP TABLE IF EXISTS #LineasFactura;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;

        -- THROW sin argumentos: re-lanza el error original conservando número, severidad y estado
        THROW;

    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_ENTREGAS_SP
    @NombreUsuario      VARCHAR(75),
    @FiltroEstado       VARCHAR(50)  = NULL,  -- NULL = Todos, o nombre exacto del estado
    @FiltroCliente      VARCHAR(100) = NULL,  -- Búsqueda parcial por nombre o identificación
    @FechaDesde         DATE         = NULL,
    @FechaHasta         DATE         = NULL
AS
BEGIN

    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Persona_ID  INT;
    DECLARE @RolEjecutor VARCHAR(50);
    DECLARE @Descripcion VARCHAR(250);

    SET @FiltroEstado  = NULLIF(TRIM(ISNULL(@FiltroEstado,  '')), '');
    SET @FiltroCliente = NULLIF(TRIM(ISNULL(@FiltroCliente, '')), '');

    BEGIN TRY

        -- Validación de usuario activo y obtención de rol
        SELECT
            @Persona_ID  = S.SESION_PER_ID,
            @RolEjecutor = R.ROL_Nombre
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Clientes solo pueden ver sus propias entregas
        -- Vendedores y Administradores ven todas
        IF @RolEjecutor NOT IN ('Administrador', 'Vendedor', 'Cliente')
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos para consultar entregas.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Validar coherencia de rango de fechas
        IF @FechaDesde IS NOT NULL AND @FechaHasta IS NOT NULL
            AND @FechaHasta < @FechaDesde
        BEGIN
            RAISERROR('Error: La fecha hasta no puede ser anterior a la fecha desde.', 16, 1);
            RETURN;
        END;

        -- Validar que el estado filtrado exista
        IF @FiltroEstado IS NOT NULL
            AND NOT EXISTS (
                SELECT 1
                FROM DBO.ESTADOS_ENTREGAS_TB
                WHERE EST_ENT_Nombre = @FiltroEstado
            )
        BEGIN
            RAISERROR('Error: El estado de entrega [%s] no existe.', 16, 1, @FiltroEstado);
            RETURN;
        END;

        SELECT
            EF.ENC_FAC_Numero                                       AS [Número Factura],
            CLI.PER_NombreCompleto                                  AS [Cliente],
            CLI.PER_Identificacion                                  AS [Identificación],
            CLI.PER_Telefono                                        AS [Teléfono],
            CLI.PER_Correo                                          AS [Correo],
            EE.EST_ENT_Nombre                                       AS [Estado Entrega],
            CONVERT(VARCHAR(10), ENT.ENC_ENT_CLI_FechaEntrega, 120) AS [Fecha Entrega],
            CASE
                WHEN ENT.ENC_ENT_CLI_FechaEntrega < CAST(GETDATE() AS DATE)
                    AND EE.EST_ENT_Nombre != 'Entregado'
                    THEN 'Vencida'
                WHEN ENT.ENC_ENT_CLI_FechaEntrega = CAST(GETDATE() AS DATE)
                    AND EE.EST_ENT_Nombre != 'Entregado'
                    THEN 'Hoy'
                WHEN EE.EST_ENT_Nombre = 'Entregado'
                    THEN 'Completada'
                ELSE
                    CONVERT(VARCHAR(5), DATEDIFF(DAY, CAST(GETDATE() AS DATE), ENT.ENC_ENT_CLI_FechaEntrega))
                    + ' día(s)'
            END                                                     AS [Tiempo Restante],
            ENT.ENC_ENT_CLI_DireccionEntrega                        AS [Dirección Entrega],
            ISNULL(ENT.ENC_ENT_CLI_Observaciones, 'N/A')            AS [Observaciones],
            CONVERT(VARCHAR(19), EF.ENC_FAC_FechaHora, 120)         AS [Fecha Factura],
            EF.ENC_FAC_Total                                        AS [Total Factura]
        FROM DBO.ENC_ENTREGAS_CLIENTES_TB ENT
        INNER JOIN DBO.ENC_FACTURAS_TB EF
            ON ENT.ENC_ENT_CLI_ENC_FAC_ID = EF.ENC_FAC_ID
        INNER JOIN DBO.PERSONAS_TB CLI
            ON EF.ENC_FAC_PER_ID = CLI.PER_ID
        INNER JOIN DBO.ESTADOS_ENTREGAS_TB EE
            ON ENT.ENC_ENT_CLI_EST_ENT_ID = EE.EST_ENT_ID
        WHERE
            -- Cliente solo ve las suyas
            (@RolEjecutor != 'Cliente' OR CLI.PER_ID = @Persona_ID)
            -- Filtro por estado
            AND (@FiltroEstado IS NULL OR EE.EST_ENT_Nombre = @FiltroEstado)
            -- Filtro parcial por nombre o identificación del cliente
            AND (
                @FiltroCliente IS NULL
                OR CLI.PER_NombreCompleto  LIKE '%' + @FiltroCliente + '%'
                OR CLI.PER_Identificacion  LIKE '%' + @FiltroCliente + '%'
            )
            -- Filtro por rango de fecha de entrega
            AND (@FechaDesde IS NULL OR ENT.ENC_ENT_CLI_FechaEntrega >= @FechaDesde)
            AND (@FechaHasta IS NULL OR ENT.ENC_ENT_CLI_FechaEntrega <= @FechaHasta)
        ORDER BY
            -- Vencidas y urgentes primero
            CASE
                WHEN EE.EST_ENT_Nombre = 'Entregado'                                
                    THEN 3
                WHEN ENT.ENC_ENT_CLI_FechaEntrega < CAST(GETDATE() AS DATE)         
                    THEN 0
                WHEN ENT.ENC_ENT_CLI_FechaEntrega = CAST(GETDATE() AS DATE)         
                    THEN 1
                ELSE                                                                      
                    2
            END,
            ENT.ENC_ENT_CLI_FechaEntrega ASC,
            CLI.PER_NombreCompleto ASC;

        -- Auditoría
        BEGIN TRY
            SET @Descripcion = 'Se usó CONSULTAR_ENTREGAS_SP';

            IF @FiltroEstado IS NOT NULL
                SET @Descripcion = @Descripcion + ', estado [' + @FiltroEstado + ']';

            IF @FiltroCliente IS NOT NULL
                SET @Descripcion = @Descripcion + ', cliente [' + LEFT(@FiltroCliente, 20) + ']';

            IF @FechaDesde IS NOT NULL OR @FechaHasta IS NOT NULL
                SET @Descripcion = @Descripcion + ', rango ['
                    + ISNULL(CONVERT(VARCHAR(10), @FechaDesde, 120), '*')
                    + ' a '
                    + ISNULL(CONVERT(VARCHAR(10), @FechaHasta, 120), '*') + ']';

            IF @FiltroEstado IS NULL AND @FiltroCliente IS NULL
               AND @FechaDesde IS NULL AND @FechaHasta IS NULL
                SET @Descripcion = @Descripcion + ' sin filtro específico (Todos).';
            ELSE
                SET @Descripcion = LEFT(@Descripcion, 247) + '.';

            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID    = @Persona_ID,
                @Accion        = 'SELECT',
                @TablaAfectada = 'ENC_ENTREGAS_CLIENTES_TB',
                @FilaAfectada  = 0,
                @Descripcion   = @Descripcion,
                @Antes         = NULL,
                @Despues       = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT            = ERROR_SEVERITY();
        DECLARE @ErrorState    INT            = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END;
GO


CREATE OR ALTER PROCEDURE DBO.MODIFICAR_ESTADO_ENTREGA_POR_FACTURA_SP
    @NombreUsuario      VARCHAR(75),    -- Responsable del cambio
    @NumeroFactura      VARCHAR(75),    -- Número de factura (ENC_FAC_Numero)
    @EnCamino           BIT = 0,        -- Botón "En camino"
    @Entregado          BIT = 0         -- Botón "Entregado"
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @Persona_ID     INT;
    DECLARE @Factura_ID     INT;
    DECLARE @Entrega_ID     INT;
    DECLARE @NuevoEstadoID  INT;
    DECLARE @NombreEstado   VARCHAR(50);
    DECLARE @Antes          VARCHAR(1000);
    DECLARE @Despues        VARCHAR(1000);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar usuario responsable (Admin o Vendedor)
        SELECT @Persona_ID = S.SESION_PER_ID
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
          AND S.SESION_Estado = 1
          AND R.ROL_Nombre IN ('Administrador', 'Vendedor', 'Cliente');

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: Usuario [%s] no tiene permisos o no está activo.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Localizar Factura y su Entrega correspondiente
        SELECT 
            @Factura_ID = F.ENC_FAC_ID,
            @Entrega_ID = E.ENC_ENT_CLI_ID
        FROM DBO.ENC_FACTURAS_TB F
        LEFT JOIN DBO.ENC_ENTREGAS_CLIENTES_TB E ON F.ENC_FAC_ID = E.ENC_ENT_CLI_ENC_FAC_ID
        WHERE F.ENC_FAC_Numero = TRIM(@NumeroFactura);

        IF @Factura_ID IS NULL
        BEGIN
            RAISERROR('Error: No se encontró la factura [%s].', 16, 1, @NumeroFactura);
            RETURN;
        END;

        IF @Entrega_ID IS NULL
        BEGIN
            RAISERROR('Error: La factura [%s] no tiene una entrega registrada.', 16, 1, @NumeroFactura);
            RETURN;
        END;

        -- Definir el nuevo estado
        IF @Entregado = 1 SET @NombreEstado = 'Entregado';
        ELSE IF @EnCamino = 1 SET @NombreEstado = 'En camino';
        ELSE
        BEGIN
            RAISERROR('Error: Instrucción de estado no válida.', 16, 1);
            RETURN;
        END;

        -- Obtener el ID del estado desde ESTADOS_ENTREGAS_TB
        SELECT @NuevoEstadoID = EST_ENT_ID 
        FROM DBO.ESTADOS_ENTREGAS_TB 
        WHERE EST_ENT_Nombre = @NombreEstado AND EST_ENT_Estado = 1;

        IF @NuevoEstadoID IS NULL
        BEGIN
            RAISERROR('Error: El estado [%s] no existe en el catálogo.', 16, 1, @NombreEstado);
            RETURN;
        END;

        -- Capturar estado actual para auditoría
        SELECT @Antes = '[EstadoID: ' + CAST(ENC_ENT_CLI_EST_ENT_ID AS VARCHAR) + ' | Factura: ' + @NumeroFactura + ']'
        FROM DBO.ENC_ENTREGAS_CLIENTES_TB WHERE ENC_ENT_CLI_ID = @Entrega_ID;

        -- Actualizar la entrega
        UPDATE DBO.ENC_ENTREGAS_CLIENTES_TB
        SET 
            ENC_ENT_CLI_EST_ENT_ID = @NuevoEstadoID,
            -- Actualiza la fecha solo si se marca como entregado
            ENC_ENT_CLI_FechaEntrega = CASE WHEN @Entregado = 1 THEN CAST(SYSDATETIME() AS DATE) ELSE ENC_ENT_CLI_FechaEntrega END
        WHERE ENC_ENT_CLI_ID = @Entrega_ID;

        -- Auditoría
        SET @Despues = '[NuevoEstado: ' + @NombreEstado + ' | FechaMod: ' + CONVERT(VARCHAR, SYSDATETIME(), 120) + ']';

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN', 'MODIFICAR_ESTADO_ENTREGA_POR_FACTURA_SP';

        INSERT INTO DBO.AUDITORIAS_TB (AUD_PER_ID, AUD_Accion, AUD_TablaAfectada, AUD_FilaAfectada, AUD_Descripcion, AUD_Antes, AUD_Despues)
        VALUES (@Persona_ID, 'UPDATE', 'ENC_ENTREGAS_CLIENTES_TB', @Entrega_ID, 
                'Cambio estado factura ' + @NumeroFactura + ' a ' + @NombreEstado, @Antes, @Despues);

        COMMIT;

        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN', NULL;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        
        EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN', NULL;

        DECLARE @ErrMsj NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR (@ErrMsj, 16, 1);
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_FACTURAS_SP
    @NombreUsuario      VARCHAR(75),
    @FiltroCliente      VARCHAR(100) = NULL,  -- Búsqueda parcial: Nombre o Identificación
    @FiltroNumero       VARCHAR(75)  = NULL,  -- Número exacto de factura
    @FechaDesde         DATE         = NULL,
    @FechaHasta         DATE         = NULL
AS
BEGIN

    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Persona_ID  INT;
    DECLARE @RolEjecutor VARCHAR(50);
    DECLARE @Descripcion VARCHAR(250);

    SET @FiltroCliente = NULLIF(TRIM(ISNULL(@FiltroCliente, '')), '');
    SET @FiltroNumero  = NULLIF(TRIM(ISNULL(@FiltroNumero,  '')), '');

    BEGIN TRY

        -- Validación de usuario activo y obtención de rol
        SELECT
            @Persona_ID  = S.SESION_PER_ID,
            @RolEjecutor = R.ROL_Nombre
        FROM DBO.SESIONES_TB S
        INNER JOIN DBO.ROLES_TB R
            ON S.SESION_ROL_ID = R.ROL_ID
        WHERE S.SESION_NombreUsuario = @NombreUsuario
            AND S.SESION_Estado = 1;

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Error: El usuario [%s] no es válido.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        IF @RolEjecutor NOT IN ('Administrador', 'Cliente')
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos para consultar facturas.', 16, 1, @NombreUsuario);
            RETURN;
        END;

        -- Validar coherencia de rango de fechas
        IF @FechaDesde IS NOT NULL AND @FechaHasta IS NOT NULL
            AND @FechaHasta < @FechaDesde
        BEGIN
            RAISERROR('Error: La fecha hasta no puede ser anterior a la fecha desde.', 16, 1);
            RETURN;
        END;

        SELECT
            EF.ENC_FAC_Numero AS [Número Factura],
            CONVERT(VARCHAR(19), EF.ENC_FAC_FechaHora, 120) AS [Fecha y Hora],
            CLI.PER_NombreCompleto AS [Cliente],
            CLI.PER_Identificacion AS [Identificación],
            TP.TIPO_PER_Nombre AS [Tipo Cliente],
            EF.ENC_FAC_Subtotal AS [Subtotal],
            EF.ENC_FAC_DescuentoTotal AS [Descuento Total],
            EF.ENC_FAC_ImpuestoPct AS [IVA %],
            EF.ENC_FAC_ImpuestoTotal AS [IVA],
            EF.ENC_FAC_CostoEnvio AS [Costo Envío],
            EF.ENC_FAC_Total AS [Total],
            CASE
                WHEN ENT.ENC_ENT_CLI_ID IS NOT NULL
                    THEN 'Sí'
                ELSE
                    'No'
            END AS [Con Entrega],
            CONVERT(VARCHAR(10), ENT.ENC_ENT_CLI_FechaEntrega, 120) AS [Fecha Entrega],
            ENT.ENC_ENT_CLI_DireccionEntrega AS [Dirección Entrega],
            ISNULL(ENT.ENC_ENT_CLI_Observaciones, 'N/A') AS [Observaciones Entrega],
            ISNULL(EE.EST_ENT_Nombre, 'N/A') AS [Estado Entrega]
        FROM DBO.ENC_FACTURAS_TB EF
        INNER JOIN DBO.PERSONAS_TB CLI
            ON EF.ENC_FAC_PER_ID = CLI.PER_ID
        INNER JOIN DBO.TIPOS_PERSONAS_TB TP
            ON CLI.PER_TIPO_PER_ID = TP.TIPO_PER_ID
        LEFT JOIN DBO.ENC_ENTREGAS_CLIENTES_TB ENT
            ON EF.ENC_FAC_ID = ENT.ENC_ENT_CLI_ENC_FAC_ID
        LEFT JOIN DBO.ESTADOS_ENTREGAS_TB EE
            ON ENT.ENC_ENT_CLI_EST_ENT_ID = EE.EST_ENT_ID
        WHERE
            -- Cliente solo ve las suyas, Administrador ve todas
            (@RolEjecutor != 'Cliente' OR CLI.PER_ID = @Persona_ID)
            -- Filtro parcial por nombre o identificación del cliente
            AND (
                @FiltroCliente IS NULL
                OR CLI.PER_NombreCompleto LIKE '%' + @FiltroCliente + '%'
                OR CLI.PER_Identificacion LIKE '%' + @FiltroCliente + '%'
            )
            -- Filtro por número de factura exacto
            AND (@FiltroNumero IS NULL OR EF.ENC_FAC_Numero = @FiltroNumero)
            -- Filtro por rango de fecha de factura
            AND (@FechaDesde IS NULL OR CAST(EF.ENC_FAC_FechaHora AS DATE) >= @FechaDesde)
            AND (@FechaHasta IS NULL OR CAST(EF.ENC_FAC_FechaHora AS DATE) <= @FechaHasta)
        ORDER BY
            EF.ENC_FAC_FechaHora DESC;

        -- Auditoría
        BEGIN TRY
            SET @Descripcion = 'Se usó CONSULTAR_FACTURAS_SP';

            IF @FiltroCliente IS NOT NULL
                SET @Descripcion = @Descripcion + ', cliente [' + LEFT(@FiltroCliente, 20) + ']';

            IF @FiltroNumero IS NOT NULL
                SET @Descripcion = @Descripcion + ', factura [' + @FiltroNumero + ']';

            IF @FechaDesde IS NOT NULL OR @FechaHasta IS NOT NULL
                SET @Descripcion = @Descripcion + ', rango ['
                    + ISNULL(CONVERT(VARCHAR(10), @FechaDesde, 120), '*')
                    + ' a '
                    + ISNULL(CONVERT(VARCHAR(10), @FechaHasta, 120), '*') + ']';

            IF @FiltroCliente IS NULL AND @FiltroNumero IS NULL
               AND @FechaDesde IS NULL AND @FechaHasta IS NULL
                SET @Descripcion = @Descripcion + ' sin filtro específico (Todos).';
            ELSE
                SET @Descripcion = LEFT(@Descripcion, 247) + '.';

            EXEC DBO.REGISTRAR_AUDITORIA_SP
                @Persona_ID    = @Persona_ID,
                @Accion        = 'SELECT',
                @TablaAfectada = 'ENC_FACTURAS_TB',
                @FilaAfectada  = 0,
                @Descripcion   = @Descripcion,
                @Antes         = NULL,
                @Despues       = NULL;
        END TRY
        BEGIN CATCH
            -- Falla en auditoría no debe interrumpir la consulta
        END CATCH

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage  NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT            = ERROR_SEVERITY();
        DECLARE @ErrorState    INT            = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END;
GO