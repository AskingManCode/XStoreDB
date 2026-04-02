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
                WHEN @TablaFiltro != '' 
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



CREATE OR ALTER PROCEDURE DBO.REGISTRAR_SESION_SP -- No agregar al API
    @CreadorCuenta  VARCHAR(75)  = NULL, -- NULL = auto-registro, sino lo crea un Administrador
    @Persona_ID     INT,
    @NombreUsuario  VARCHAR(75),
    @PasswordHash   VARCHAR(255),
    @NombreRol      VARCHAR(50)
AS
BEGIN

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @CreadorCuenta_ID   INT;
    DECLARE @Rol_ID             INT;
 
    SET @NombreUsuario = TRIM(ISNULL(@NombreUsuario, ''));
    SET @NombreRol     = TRIM(ISNULL(@NombreRol, ''));

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Validación de existencia y estado de la persona destino
        IF NOT EXISTS (
            SELECT 1 
            FROM DBO.PERSONAS_TB
            WHERE PER_ID = @Persona_ID 
                AND PER_Estado = 1
        )
        BEGIN
            RAISERROR('La persona no existe o está inactiva.', 16, 1);
            RETURN;
        END
        
        -- Validación de permisos del creador
        IF @CreadorCuenta IS NULL
        BEGIN
            -- Auto-registro: la persona destino debe ser válida y no ser el sistema
            IF @Persona_ID = 1
            BEGIN
                RAISERROR('Esta cuenta no tiene permisos para auto-registrarse.', 16, 1);
                RETURN;
            END
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
            RAISERROR('El nombre de usuario no puede estar vacío.', 16, 1);
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
            RAISERROR('Hash de la contraseña no válido.', 16, 1);
            RETURN;
		END

        -- Obtener ID del rol
        SELECT @Rol_ID = ROL_ID 
        FROM DBO.ROLES_TB 
        WHERE ROL_Nombre = @NombreRol;
 
        IF @Rol_ID IS NULL
        BEGIN
            RAISERROR('Error: El rol [%s] no existe.', 16, 1, @NombreRol);
            RETURN;
        END;

        -- Restricción: rol 'Sistema' solo para persona ID 1
        IF @NombreRol = 'SISTEMA' AND @Persona_ID != 1
        BEGIN
            RAISERROR('Error: El rol Sistema está reservado para la cuenta del sistema.', 16, 1);
            RETURN;
        END;

        -- Validación de unicidad de rol por persona (antes del INSERT)
        IF EXISTS (
            SELECT 1 
            FROM DBO.SESIONES_TB
            WHERE SESION_PER_ID = @Persona_ID 
                AND SESION_ROL_ID = @Rol_ID
        )
        BEGIN
            RAISERROR('La persona ya tiene una sesión registrada con el rol [%s].', 16, 1, @NombreRol);
            RETURN;
        END;

        -- Registrar sesión
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

		DECLARE @ErrorMessage	NVARCHAR(4000)	= ERROR_MESSAGE();
		DECLARE @ErrorSeverity	INT				= ERROR_SEVERITY();
		DECLARE @ErrorState		INT				= ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

    END CATCH
END;
GO



CREATE OR ALTER PROCEDURE DBO.CONSULTAR_TIPOS_PRODUCTOS_SP
    @NombreUsuario  VARCHAR(75)    -- Responsable
AS 
BEGIN
    
    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;

    BEGIN TRY
        
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
    @NombreUsuario VARCHAR(75) -- Responsable
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
          AND S.SESION_Estado = 1
          AND R.ROL_Nombre = 'Administrador';

        IF @Persona_ID IS NULL
        BEGIN
            RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos.', 16, 1, @NombreUsuario);
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
    @NombreUsuario  VARCHAR(75),             -- Responsable
    @Filtro         VARCHAR(20)     = NULL,  -- Administradores, Vendedores, Clientes, Proveedores, Null = Todos
    @Busqueda       VARCHAR(100)    = NULL   -- Búsqueda parcial en Identificación, Nombre, Correo, Teléfono
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @Persona_ID INT;
    DECLARE @BusquedaLike VARCHAR(102);
    DECLARE @Descripcion VARCHAR(250);

    SET @Filtro = UPPER(TRIM(ISNULL(@Filtro, '')));

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

        -- Filtro inválido
        IF @Filtro NOT IN ('ADMINISTRADORES', 'VENDEDORES', 'CLIENTES', 'PROVEEDORES', '')
        BEGIN
            RAISERROR('Error: Filtro [%s] no válido. Use: Administradores, Vendedores, Clientes, Proveedores o deje vacío para mostrar a todos.', 16, 1, @Filtro);
            RETURN;
        END;

        -- Personas con roles (Administradores, Vendedores, Clientes)
        SELECT 
            P.PER_ID AS [ID Persona]
            , P.PER_Identificacion AS [Identificación]
            , P.PER_NombreCompleto AS [Nombre Completo]
            , P.PER_Telefono AS [Teléfono]
            , P.PER_Correo AS [Correo]
            , P.PER_Direccion AS [Dirección]
            , TP.TIPO_PER_Nombre AS [Tipo Descuento]
            , CONVERT(VARCHAR(5), TP.TIPO_PER_DescuentoPct) + '%' AS [Descuento %]
            , R.ROL_Nombre AS [Rol]
            , S.SESION_NombreUsuario AS [Nombre Usuario]
            , CONVERT(VARCHAR(10), P.PER_FechaRegistro, 120) AS [Fecha Registro]
            , CASE 
                WHEN P.PER_Estado = 1 AND S.SESION_Estado = 1 AND R.ROL_Estado = 1
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
            AND (@Filtro = '' -- Filtro aplicado
                OR (@Filtro = 'ADMINISTRADORES' AND R.ROL_Nombre = 'Administrador')
                OR (@Filtro = 'VENDEDORES' AND R.ROL_Nombre = 'Vendedor')
                OR (@Filtro = 'CLIENTES' AND R.ROL_Nombre = 'Cliente'))
            AND (@Busqueda IS NULL -- Filtro de búsqueda específica
                OR P.PER_Identificacion LIKE @BusquedaLike
                OR P.PER_NombreCompleto LIKE @BusquedaLike
                OR P.PER_Correo LIKE @BusquedaLike
                OR P.PER_Telefono LIKE @BusquedaLike)
        UNION ALL
        -- Proveedores 
        SELECT 
            P.PER_ID AS [ID Persona]
            , P.PER_Identificacion AS [Identificación]
            , P.PER_NombreCompleto AS [Nombre Completo]
            , P.PER_Telefono AS [Teléfono]
            , P.PER_Correo AS [Correo]
            , P.PER_Direccion AS [Dirección]
            , TP.TIPO_PER_Nombre AS [Tipo Descuento]
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
        WHERE P.PER_ID != 1  -- Reservado para SISTEMA
            AND (@Filtro IN ('PROVEEDORES', '') -- Filtro específico para proveedores
                AND (
                    @Filtro = 'PROVEEDORES'  
                        OR @Filtro = ''  -- Siempre mostrar proveedores en filtro vacío también
                ))
            AND (@Busqueda IS NULL -- Filtro de búsqueda específica
                OR P.PER_Identificacion LIKE @BusquedaLike
                OR P.PER_NombreCompleto LIKE @BusquedaLike
                OR P.PER_Correo LIKE @BusquedaLike
                OR P.PER_Telefono LIKE @BusquedaLike)
        ORDER BY [ID Persona], [Nombre Completo], [Rol];

        BEGIN TRY
            SET @Descripcion = 'Se usó CONSULTAR_PERSONAS_SP' + 
                CASE 
                    WHEN @Filtro != '' 
                        THEN ' con filtro [' + @Filtro + '].'
                    ELSE 
                        ' sin filtro específico (Todos).'
                END;

            IF @Busqueda IS NOT NULL
                SET @Descripcion = LEFT(@Descripcion, 230) + ' Búsqueda: ' + LEFT(@Busqueda, 15) + '.';
        
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



CREATE OR ALTER PROCEDURE DBO.REGISTRAR_USUARIO_SP
    @NombreUsuario      VARCHAR(75)     = NULL,     -- Responsable (NULL = auto-registro)
    @Identificacion     VARCHAR(50),                -- Identificación
    @NombreCompleto     VARCHAR(150),               -- Nombre completo
    @Telefono           VARCHAR(25)     = NULL,     -- Teléfono
    @Correo             VARCHAR(150)    = NULL,     -- Correo
    @Direccion          VARCHAR(175)    = NULL,     -- Dirección
    @NewUser            VARCHAR(75),                -- Nombre de usuario para la sesión
    @PasswordHash       VARCHAR(255),               -- Contraseña hasheada
    @NombreRol          VARCHAR(50),                -- Administrador, Vendedor, Cliente, Null(Si es vendedor)
    @EsProveedor        BIT             = 0         -- 1 = Registrar solo como proveedor (sin sesión)
AS
BEGIN
 
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
 
    DECLARE @Persona_ID_Ejecutor   INT;
    DECLARE @Persona_ID_Nueva      INT;
    DECLARE @Tipo_Per_ID           INT;
    DECLARE @Rol_Normalizado       VARCHAR(50);
    DECLARE @TipoPersonaNombre     VARCHAR(50);
 
    -- Normalización
    SET @Identificacion  = TRIM(ISNULL(@Identificacion, ''));
    SET @NombreCompleto  = TRIM(ISNULL(@NombreCompleto, ''));
    SET @Telefono        = NULLIF(TRIM(@Telefono), '');
    SET @Direccion       = NULLIF(TRIM(@Direccion), '');
    SET @Correo          = NULLIF(TRIM(@Correo), '');
    SET @NewUser         = TRIM(ISNULL(@NewUser, ''));
    SET @Rol_Normalizado = UPPER(TRIM(ISNULL(@NombreRol, '')));
 
    BEGIN TRY
 
        BEGIN TRANSACTION;
 
        -- Validaciones de parámetros obligatorios
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
 
        IF @EsProveedor = 0 AND LEN(@NewUser) = 0
        BEGIN
            RAISERROR('Error: El nombre de usuario no puede estar vacío.', 16, 1);
            RETURN;
        END;
 
        IF @EsProveedor = 0 AND LEN(@PasswordHash) = 0
        BEGIN
            RAISERROR('Error: La contraseña no puede estar vacía.', 16, 1);
            RETURN;
        END;
        
        IF @EsProveedor = 1 AND LEN(@Rol_Normalizado) > 0
        BEGIN
            RAISERROR('Error: Al registrar un proveedor puro (@EsProveedor = 1), no se debe especificar un rol.', 16, 1);
            RETURN;
        END;
 
        -- Validación de permisos y tipo de registro
        IF @NombreUsuario IS NULL
        BEGIN
            -- Auto-registro: Solo permite rol Cliente
            IF @Rol_Normalizado != 'CLIENTE'
            BEGIN
                RAISERROR('Error: El auto-registro solo está permitido para el rol Cliente.', 16, 1);
                RETURN;
            END;
 
            -- Para auto-registro, el ejecutor del Procedimiento será la persona misma una vez creada
            -- NULL temporalmente para indicar que no hay ejecutor externo
            SET @Persona_ID_Ejecutor = NULL;
        END
        ELSE
        BEGIN
            -- Verificar que el ejecutor del SP sea un Administrador válido
            SELECT @Persona_ID_Ejecutor = S.SESION_PER_ID
            FROM DBO.SESIONES_TB S
            INNER JOIN DBO.ROLES_TB R 
                ON S.SESION_ROL_ID = R.ROL_ID
            WHERE S.SESION_NombreUsuario = @NombreUsuario
                AND S.SESION_Estado = 1
                AND R.ROL_Nombre = 'Administrador';
 
            IF @Persona_ID_Ejecutor IS NULL
            BEGIN
                RAISERROR('Acceso denegado: El usuario [%s] no tiene permisos de Administrador.', 16, 1, @NombreUsuario);
                RETURN;
            END;
        END;
 
        -- Verificar si la persona ya existe por identificación
        SELECT @Persona_ID_Nueva = PER_ID 
        FROM DBO.PERSONAS_TB 
        WHERE PER_Identificacion = @Identificacion;
 
        -- Caso: Persona existe y es proveedor que quiere ser cliente
        IF @Persona_ID_Nueva IS NOT NULL
        BEGIN
            -- Verificar si es proveedor
            IF NOT EXISTS(SELECT 1 FROM DBO.PROVEEDORES_TB WHERE PRV_PER_ID = @Persona_ID_Nueva)
            BEGIN
                RAISERROR('Error: Esta persona ya tiene una cuenta registrada en el sistema.', 16, 1);
                RETURN;
            END;
 
            -- Es proveedor, solo puede registrarse como Cliente
            IF @Rol_Normalizado != 'CLIENTE'
            BEGIN
                RAISERROR('Error: Un proveedor existente solo puede registrarse como Cliente.', 16, 1);
                RETURN;
            END;
 
            -- Verificar que no tenga ya sesión con este rol
            IF EXISTS(
                SELECT 1 
                FROM DBO.SESIONES_TB S
                INNER JOIN DBO.ROLES_TB R ON S.SESION_ROL_ID = R.ROL_ID
                WHERE S.SESION_PER_ID = @Persona_ID_Nueva 
                AND UPPER(R.ROL_Nombre) = @Rol_Normalizado
            )
            BEGIN
                RAISERROR('Error: Esta persona ya tiene una sesión registrada con el rol [%s].', 16, 1, @NombreRol);
                RETURN;
            END;
 
            -- CASO ESPECIAL: Proveedor existente crea su propia sesión de cliente
            -- La persona misma es responsable de la auditoría (similar a auto-registro)
            EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID_Nueva;
            EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     'REGISTRAR_USUARIO_SP';
 
            -- Crear una nueva sesión para la persona registrada
            EXEC DBO.REGISTRAR_SESION_SP
                @CreadorCuenta  = @NombreUsuario,  -- NULL si es auto-registro, admin si no
                @Persona_ID     = @Persona_ID_Nueva,
                @NombreUsuario  = @NewUser,
                @PasswordHash   = @PasswordHash,
                @NombreRol      = @NombreRol;
 
            COMMIT;
            RETURN;
        END;
 
        -- Caso de que persona no exista
        -- Determinar el Tipo de Persona según el Rol
        SET @TipoPersonaNombre = CASE @Rol_Normalizado
                                    WHEN 'CLIENTE' THEN 'Cliente Normal'
                                    WHEN 'VENDEDOR' THEN 'Cliente Normal'
                                    WHEN 'ADMINISTRADOR' THEN 'Administrador'
                                    ELSE NULL
                                 END;
 
        IF @TipoPersonaNombre IS NULL AND @EsProveedor = 0
        BEGIN
            RAISERROR('Error: Rol [%s] no válido. Use: Administrador, Vendedor o Cliente.', 16, 1, @NombreRol);
            RETURN;
        END;
 
        -- Para proveedor, usar 'Cliente Normal' como tipo de persona
        IF @EsProveedor = 1
            SET @TipoPersonaNombre = 'Cliente Normal';
 
        -- Obtener el ID del Tipo de Persona
        SELECT @Tipo_Per_ID = TIPO_PER_ID 
        FROM DBO.TIPOS_PERSONAS_TB 
        WHERE TIPO_PER_Nombre = @TipoPersonaNombre;
 
        IF @Tipo_Per_ID IS NULL
        BEGIN
            RAISERROR('Error: Tipo de persona [%s] no encontrado en el sistema.', 16, 1, @TipoPersonaNombre);
            RETURN;
        END;
        
        -- Si hay ejecutor (admin), usarlo. Si no, usa NULL temporalmente
        IF @Persona_ID_Ejecutor IS NOT NULL
        BEGIN
            EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID_Ejecutor;
        END
        ELSE
        BEGIN
            -- Auto-registro: No hay persona aún, usa 0 y el trigger entiende que debe usar el id de la persona
            EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', 0;
        END
        
        EXEC SP_SET_SESSION_CONTEXT 'ORIGEN', 'REGISTRAR_USUARIO_SP';
 
        -- Insertar Persona
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
 
        --SET @Persona_ID_Nueva = SCOPE_IDENTITY();

        SELECT @Persona_ID_Nueva = PER_ID
        FROM DBO.PERSONAS_TB
        WHERE PER_Identificacion = @Identificacion
            AND PER_NombreCompleto = @NombreCompleto;
        
        -- Si es auto-registro, la persona recién creada es responsable
        -- Si es admin, mantiene al admin como responsable
        IF @Persona_ID_Ejecutor IS NULL
        BEGIN
            -- Auto-registro: La persona misma es responsable de su sesión
            EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID_Nueva;
        END

        -- Si es admin, el contexto ya tiene @Persona_ID_Ejecutor, no cambia
        -- Caso: Es proveedor (solo insertar en PROVEEDORES_TB, no crear sesión)
        IF @EsProveedor = 1
        BEGIN
            INSERT INTO DBO.PROVEEDORES_TB (PRV_PER_ID)
            VALUES (@Persona_ID_Nueva);
 
            EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
            EXEC SP_SET_SESSION_CONTEXT 'ORIGEN',     NULL;
 
            COMMIT;
            RETURN;
        END;
        
        -- Crear sesión
        EXEC DBO.REGISTRAR_SESION_SP
            @CreadorCuenta  = @NombreUsuario,
            @Persona_ID     = @Persona_ID_Nueva,
            @NombreUsuario  = @NewUser,
            @PasswordHash   = @PasswordHash,
            @NombreRol      = @NombreRol;
 
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


/*CREATE OR ALTER PROCEDURE CONSULTAR_NOMBRE_PROVEEDORES
    @NombreUsuario  VARCHAR(75),    -- Responsable
AS
BEGIN
    
END;
GO*/

EXEC CONSULTAR_TIPOS_PERSONAS_SP
    @NombreUsuario = 'AskingMansOz';

EXEC REGISTRAR_TIPO_PERSONA_SP
    @NombreUsuario = 'AskingMansOz',
    @Nombre = 'Vendedor',
    @DescuentoPct = 15,
    @MontoMeta = 0;

EXEC MODIFICAR_TIPO_PERSONA_SP
    @NombreUsuario = 'AskingMansOz',
    @Nombre = 'Cliente Frecuente',
    @NuevoNombre = 'Cliente Frecuente',
    @NuevoDescuentoPct = 10,
    @NuevoMontoMeta = 500000,
    @NuevoEstado = 1;

EXEC CONSULTAR_PERSONAS_SP
    @NombreUsuario = 'AskingMansOz',
    @Filtro = 'ADMINISTRADORES';

EXEC CONSULTAR_AUDITORIAS_SP
	@NombreUsuario = 'AskingMansOz',
    --@FechaFiltro = '2026-03-29',
	@TablaFiltro = 'PERSONAS_TB';


-- CREATE OR ALTER PROCEDURE 

/*
	SP's XStore

	X REGISTRAR_AUDITORIA_SP (Parámetros - Persona_id, accion[insert, delete, update], tablaAfectada, Descripción[mas de 10 letras])
	X CONSULTA_AUDITORIAS_SP (Select y join de todas las auditorias con nombre de persona)

	X CONSULTAR_ROLES_SP (Select simple Roles)
	X REGISTRAR_ROL_SP (Insert a Roles)
	X MODIFICAR_ROL_SP (Update a Roles) 

	X CONSULTAR_TIPOS_PRODUCTOS_SP (Select simple tipos_productos)
	X REGISTRAR_TIPO_PODUCTO_SP (Insert a tipos_prodcutos)
	X MODIFICAR_TIPO_PRODUCTO_SP (Update a Tipos_productos)

	X CONSULTAR_MARCAS_PRODUCTOS_SP (select simple marcas)
	X REGISTRAR_MARCAS_PRODUCTOS_SP (Insert a marcas)
	X MODIFICAR_MARCA_PRODUCTO_SP (Update a marcas)

    X CONSULTAR_UBICACIONES_SP (Select simple nombre)
	X REGISTRAR_UBICACION_SP (Insert UBI_INVENTARIOS)
	X MODIFICAR_UBICACION_SP (Update a UBI_INVENTARIOS)

    -----------------------------------------------------------------------------------------------------------------------------------------------------------------
	CONSULTAR_INVENTARIOS_UBICACION_SP (Select y join por ubicaciones)
	CONSULTAR_INVENTARIOS_TIPOS_PRODUCTOS_SP (Select y join por productos)
	CONSULTAR_INVENTARIOS_MARCAS_SP (Select y join por marca)
	CONSULTAR_INVENTARIOS_PROVEEDORES_SP (Select y join por proveedores)
	MODIFICAR_STOCK_MINIMO_SP (Update StockMinimo de un producto)

	CONSULTAR_PRODUCTOS_SP (select con joins)
	CONSULTAR_PRODUCTOS_MARCA_SP (select con join, marcas)
	CONSULTAR_PRODUCTOS_TIPO_SP (Select con join tipos)
	CONSULTAR_PRODUCTOS_PROVEEDORES_SP (Select con join proveedores)

	REGISTRAR_NUEVO_PRODUCTO_SP (Incluye Tipo, Marca, Proveedor y descuento null porque apenas se crea el producto, se busca en inventario y en ubicación y 
								se aumenta la cantidad del producto para el inventario de esa ubicación en específico, si no existe 
								se agrega a inventario y se le pone la cantidad agregada al registro)
	MODIFICAR_PRODUCTO_SP (UPDATE al tipo, marca, proveedor, y datos generales del producto, no aplica update al descuento)

	X CONSULTAR_CAT_DESCUENTOS_SP (Select simple)
	X REGISTRAR_CAT_DESCUENTO_SP (Insert Cat_descuentos)
	X MODIFICAR_CAT_DESCUENTO_SP (Update cat_descuento)

	CONSULTAR_DESCUENTOS_SP (Select y join a cat_descuentos)
	CONSULTAR_CAT_DESCUENTO_PRODUCTO_SP (Select categoría de descuento, el descuento y que producto)
	-- VIEW CONSULTAR_PRODUCTOS_SIN_DESCUENTO_SP (Select productos que no tengan descuentos aplicados)
	-- VIEW CONSULTAR_PRODUCTOS_CON_DESCUENTO_SP (Selecy productos que si tengan descuentos aplicados y cuanto y por cuanto tiempo)
	REGISTRAR_DESCUENTO_SP (Incluye la categoría_Descuento)
	MODIFICAR_DESCUENTO_SP (Update Descuentos)
	CAMBIAR_ESTADO_DESCUENTO_SP (Activo o Inactivo)
	APLICAR_DESCUENTO_PRODUCTO_SP (Se aplica un desc_ID a un producto o varios)
	QUITAR_DESCUENTO_PRODUCTO_SP (Se aplica un null a la referencia del descuento que tenía antes)
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------

	X REGISTRAR_SESION_SP
	VERIFICAR_SESION_SP (Devuelve el nombre de Usuario para mostrarlo en la información de cuenta, sino, error, verifica que el usuario exista)
	MODIFICAR_SESION_SP (Cambia contraseña si se cambia o nombre de usuario, Recordar NombreUsuario es UNIQUE)

	-------------------------------------------------------------------------------------------------------------------------------------------------------
	X CONSULTAR_TIPOS_PERSONAS_SP (Select simple)
	X REGISTRAR_TIPO_PERSONA_SP (Insert tipos_personas)
	X MODIFICAR_TIPO_PERSONA_SP (Update tipos_personas, activo o inactivo)

	X CONSULTAR_PERSONAS_SP (Select join con tipo_persona, vendedor(empleados) o administradores o proveedores, o todo junto)

	REGISTRAR_USUARIO_SP (Insert a personas que usa tipo_personaID, insert a sesiones que usa rolID y personaID (Entra como varchar y busca el ID para asignarlo a la tabla), 
							Rol Administrador, Vendedor(Empleado) o Cliente, si los datos ya existen y es un proveedor previamente registrado se le puede 
							agregar como rol cliente a este proveedor para que haga compras en caso de que decida ser cliente)

	MODIFICAR_PERSONA_SP (Update a personas) -- El tipo de persona no se cambia porque se hará automático según las comprás realizadas

	REGISTRAR_PROVEEDOR_SP (Agrega a Persona, Lo asigna como proveedor en la tabla de proveedores, Se le asigna tipo de persona cliente_normal 0%)

	MODIFICAR_PROVEEDOR_SP (Update en Personas proveedores, activo o inactivo)

	Nota: 
	1. EL registro de un usuario del sistema es diferente al registro de un proveedor (este no tiene rol ni cuenta inicialmente)
	2. Todo debe tener auditoría
	3. Los triggers tienen que funcionar con sp y sin sp, osea auditoría real sin margen de error.
	-------------------------------------------------------------------------------------------------------------------------------------------------------

	CONSULTAR_ESTADOS_ENTREGA_SP (Select simple estados_entrega)
	REGISTRAR_ESTADO_ENTREGA_SP (Insert estados_entrega)
	MODIFICAR_ESTADO_ENTREGA_SP (Activar o Inactivar)

	FACTURAR_CLIENTE_SP (crear encabezados, referenciar cliente, agregar entrega si aplica y referenciar el estado y detallar factura, 
						agregar productos, verificar descuentos, aplicar descuentos si existen, 
						agregar cantidad compra al tipo de cliente, verificar suma de montos, aplicar impuestos)
*/