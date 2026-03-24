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
CREATE OR ALTER PROCEDURE DBO.REGISTRAR_AUDITORIA_SP
	@Persona_ID			INT, -- ID de la Persona Responsable
	@Accion				VARCHAR(25),
	@TablaAfectada		VARCHAR(75),
	@FilaAfectada		BIGINT,
	@Descripcion		VARCHAR(250)
AS
BEGIN
	
	SET NOCOUNT ON;
	SET XACT_ABORT ON; -- Aborta si hay error de ejecución

	BEGIN TRY
		
		-- NORMALIZACIÓN
		SET @Accion = UPPER(TRIM(ISNULL(@Accion, '')));
		SET @TablaAfectada = UPPER(TRIM(ISNULL(@TablaAfectada, '')));
		SET @Descripcion = TRIM(ISNULL(@Descripcion, ''));

		-- VALIDACIONES
		IF NOT EXISTS(
			SELECT 1
			FROM DBO.PERSONAS_TB
			WHERE PER_ID = @Persona_ID
		)
		BEGIN
			RAISERROR('Persona_ID [%d] no existe para auditoría.', 16, 1, @Persona_ID);
		END
		
		IF @Accion NOT IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
		BEGIN
			RAISERROR('Acción [%s] no válida para auditoría.', 16, 1, @Accion);
		END

		IF LEN(@TablaAfectada) < 1
		BEGIN
			RAISERROR('Tabla no válida para auditoría', 16, 1)
		END

		IF (@Accion = 'SELECT' AND @FilaAfectada != 0)
		BEGIN
			RAISERROR('ID de fila afectada no válido para auditoría.', 16, 1);
		END

		IF @Accion != 'SELECT' AND @FilaAfectada <= 0
		BEGIN
			RAISERROR('ID de fila afectada no válido para auditoría.', 16, 1);
		END

		IF LEN(@Descripcion) <= 10
		BEGIN
			RAISERROR('La descripción para la auditoría es muy corta.', 16, 10);
		END

		INSERT INTO DBO.AUDITORIAS_TB(
			AUD_PER_ID, AUD_Accion, AUD_TablaAfectada, AUD_FilaAfectada, AUD_Descripcion
		)
		VALUES (
			@Persona_ID, @Accion, @TablaAfectada, @FilaAfectada, @Descripcion
		);

	END TRY
	BEGIN CATCH
		
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
		DECLARE @ErrorState INT = ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_AUDITORIAS_SP
	@NombreUsuario		VARCHAR(75), -- Responsable 
	@FechaFiltro		DATE = NULL,
	@TablaFiltro		VARCHAR(75) = NULL	
AS
BEGIN

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; -- Evita que se bloqueen otras tablas de alta transaccionalidad
	
	DECLARE @Persona_ID INT;

	BEGIN TRY
		
		-- VALIDACIÓN DE PERMISO Y OBTENER ID
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
			, A.AUD_FechaHora AS [Fecha y Hora]
		FROM DBO.AUDITORIAS_TB A
		INNER JOIN DBO.PERSONAS_TB P
			ON A.AUD_PER_ID = P.PER_ID
		WHERE (@FechaFiltro IS NULL 
				OR CAST(A.AUD_FechaHora AS DATE) = @FechaFiltro) AND
				(@TablaFiltro IS NULL OR A.AUD_TablaAfectada = UPPER(TRIM(@TablaFiltro)))
		ORDER BY A.AUD_FechaHora DESC; -- Fechas recientes primero

		EXEC REGISTRAR_AUDITORIA_SP
			@Persona_ID = @Persona_ID,
			@Accion = 'SELECT',
			@TablaAfectada = 'AUDITORIAS_TB',
			@FilaAfectada = 0,
			@Descripcion = 'Se usó CONSULTAR_AUDITORIAS_SP.'

	END TRY
	BEGIN CATCH
		
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
		DECLARE @ErrorState INT = ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.CONSULTAR_ROLES_SP
	@NombreUsuario		VARCHAR(75) -- Responsable
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
			ROL_Nombre AS [Rol]
			, ROL_Estado AS [Estado]
		FROM DBO.ROLES_TB;

		EXEC REGISTRAR_AUDITORIA_SP
			@Persona_ID = @Persona_ID,
			@Accion = 'SELECT',
			@TablaAfectada = 'ROLES_TB',
			@FilaAfectada = 0,
			@Descripcion = 'Se usó CONSULTAR_ROLES_SP.'

	END TRY
	BEGIN CATCH

		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
		DECLARE @ErrorState INT = ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO


CREATE OR ALTER PROCEDURE DBO.REGISTRAR_ROL_SP
	@NombreUsuario		VARCHAR(75), -- Responsable
	@NuevoRol			VARCHAR(50)
AS
BEGIN

	SET NOCOUNT ON;

	DECLARE @Persona_ID INT;
	SET @NuevoRol = TRIM(ISNULL(@NuevoRol, ''))

	BEGIN TRY

		BEGIN TRANSACTION;

		-- VALIDACIÓN DE PERMISO Y OBTENER ID
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
			ROLLBACK;
			RETURN;
		END;

		IF LEN(@NuevoRol) <= 0
		BEGIN
			RAISERROR('Error: El rol no es válido.', 16, 1);
			ROLLBACK;
			RETURN;
		END

		-- Guarda Persona ID
		EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID;

		INSERT INTO ROLES_TB (ROL_Nombre)
		VALUES (@NuevoRol);

		COMMIT;

	END TRY
	BEGIN CATCH
		
		IF @@TRANCOUNT > 0 ROLLBACK;

		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
		DECLARE @ErrorState INT = ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE DBO.MODIFICAR_ROL_SP
	@NombreUsuario		VARCHAR(75), -- Responsable
	@NombreRol			VARCHAR(50),
	@NuevoNombreRol		VARCHAR(50) = NULL,
	@NuevoEstado		BIT = NULL
AS
BEGIN
	
	SET NOCOUNT ON;

	DECLARE @Persona_ID INT;
	SET @NombreRol = TRIM(ISNULL(@NombreRol, ''));

	BEGIN TRY

		BEGIN TRANSACTION;

		-- VALIDACIÓN DE PERMISO Y OBTENER ID
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
			ROLLBACK;
			RETURN;
		END;

		IF NOT EXISTS (
			SELECT 1
			FROM DBO.ROLES_TB
			WHERE ROL_Nombre = @NombreRol
		)
		BEGIN
			RAISERROR('Error: El rol [%s] no existe.', 16, 1, @NombreRol);
			ROLLBACK;
			RETURN;
		END

		-- Guarda Persona ID
		EXEC SP_SET_SESSION_CONTEXT 'PERSONA_ID', @Persona_ID; 

		IF (@NuevoNombreRol IS NOT NULL AND LEN(TRIM(@NuevoNombreRol)) > 0) OR @NuevoEstado IS NOT NULL
		BEGIN
			UPDATE DBO.ROLES_TB
			SET	ROL_Nombre = ISNULL(TRIM(@NuevoNombreRol), ROL_Nombre),
				ROL_Estado = ISNULL(@NuevoEstado, ROL_Estado)
			WHERE ROL_Nombre = @NombreRol;
		END

		COMMIT;

	END TRY
	BEGIN CATCH
		
		IF @@TRANCOUNT > 0 ROLLBACK;

		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
		DECLARE @ErrorState INT = ERROR_STATE();

		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)

	END CATCH
END;
GO

EXEC CONSULTAR_AUDITORIAS_SP
	@NombreUsuario = 'AskingMansOz'

-- CREATE OR ALTER PROCEDURE 

/*
	SP's XStore

	X REGISTRAR_AUDITORIA_SP (Parámetros - Persona_id, accion[insert, delete, update], tablaAfectada, Descripción[mas de 10 letras])
	X CONSULTA_AUDITORIAS_SP (Select y join de todas las auditorias con nombre de persona)

	X CONSULTAR_ROLES_SP (Select simple Roles)
	X REGISTRAR_ROL_SP (Insert a Roles)
	X MODIFICAR_ROL_SP (Update a Roles) 

	CONSULTAR_UBICACIONES_SP (Select simple nombre)
	REGISTRAR_UBICACION_SP (Insert UBI_INVENTARIOS)
	MODIFICAR_UBICACION_SP (Update a UBI_INVENTARIOS)
	CAMBIAR_ESTADO_UBICACION_SP (Activar o Inactivar Ubicacion)

	CONSULTAR_INVENTARIOS_UBICACION_SP (Select y join por ubicaciones)
	CONSULTAR_INVENTARIOS_TIPOS_PRODUCTOS_SP (Select y join por productos)
	CONSULTAR_INVENTARIOS_MARCAS_SP (Select y join por marca)
	CONSULTAR_INVENTARIOS_PROVEEDORES_SP (Select y join por proveedores)
	MODIFICAR_STOCK_MINIMO_SP (Update StockMinimo de un producto)
	CAMBIAR_ESTADO_INVENTARIO_SP (Activar o Inactivar inventario)

	CONSULTAR_TIPOS_PRODUCTOS_SP (Select simple tipos_productos)
	REGISTRAR_TIPO_PODUCTO_SP (Insert a tipos_prodcutos)
	MODIFICAR_TIPO_PRODUCTO_SP (Update a Tipos_productos)
	CAMBIAR_ESTADO_TIPO_PRODUCTO_SP (Activo o inactivo)

	CONSULTAR_MARCAS_PRODUCTOS_SP (select simple marcas)
	REGISTRAR_MARCAS_PRODUCTOS_SP (Insert a marcas)
	MODIFICAR_MARCA_PRODUCTO_SP (Update a marcas)
	CAMBIAR_ESTADO_MARCA_SP (Activo o Inactivo)

	CONSULTAR_TIPOS_PERSONAS_SP (Select simple)
	REGISTRAR_TIPO_PERSONA_SP (Insert tipos_personas)
	MODIFICAR_TIPO_PERSONA_SP (Update tipos_personas)
	CAMBIAR_ESTADO_TIPO_PERSONA_SP (Activo o Inactivo)

	CONSULTAR_PERSONAS_SP (Select join con tipo_persona)
	REGISTRAR_USUARIO_SP (Insert a personas que usa tipo_personaID, insert a sesiones que usa rolID y personaID, 
							Rol Administrador, Vendedor o Cliente, si los datos ya existen y es proveedor se le puede 
							agregar como rol cliente a este proveedor para que haga compras en caso de que decida ser cliente)
	MODIFICAR_PERSONA_SP (Update a personas) -- El tipo de persona no se cambia porque se hará automático según las comprás realizadas
	CAMBIAR_ESTADO_PERSONA_SP (Activo o Inactivo)

	CONSULTAR_PROVEEDORES_SP (select y join con personas)
	REGISTRAR_PROVEEDOR_SP (Agrega a Persona, Lo asigna como proveedor en la tabla de proveedores, Se le asigna tipo de persona cliente_normal 0% )
	MODIFICAR_PROVEEDOR_SP (Update en Personas proveedores)
	CAMBIAR_ESTADO_PROVEEDOR_SP (Activo o Inactivo)

	CONSULTAR_CATEGORIAS_DESCUENTOS_SP (Select simple)
	REGISTRAR_CATEGORIA_DESCUENTO_SP (Insert Cat_descuentos)
	MODIFICAR_CAT_DESCUENTO_SP (Update cat_descuento)
	CAMBIAR_ESTADO_CAT_DESCUENTO_SP (Activo o Inactivo)

	CONSULTAR_DESCUENTOS_SP (Select y join a cat_descuentos)
	CONSULTAR_CAT_DESCUENTO_PRODUCTO_SP (Select categoría de descuento, el descuento y que producto)
	CONSULTAR_PRODUCTOS_SIN_DESCUENTO_SP (Select productos que no tengan descuentos aplicados)
	CONSULTAR_PRODUCTOS_CON_DESCUENTO_SP (Selecy productos que si tengan descuentos aplicados y cuanto y por cuanto tiempo)
	REGISTRAR_DESCUENTO_SP (Incluye la categoría_Descuento)
	MODIFICAR_DESCUENTO_SP (Update Descuentos)
	CAMBIAR_ESTADO_DESCUENTO_SP (Activo o Inactivo)
	APLICAR_DESCUENTO_PRODUCTO_SP (Se aplica un desc_ID a un producto o varios)
	QUITAR_DESCUENTO_PRODUCTO_SP (Se aplica un null a la referencia del descuento que tenía antes)

	VERIFICAR_SESION_SP (Devuelve el nombre de Usuario para mostrarlo en la información de cuenta, sino, error, verifica que el usuario exista)
	MODIFICAR_SESION_SP (Cambia contraseña si se cambia o nombre de usuario, Recordar NombreUsuario es UNIQUE)
	MODIFICAR_TOKENS_SP (Cambia los tokens)
	CAMBIAR_ESTADO_USUARIO_SP (Activar o Inactivar)

	CONSULTAR_PRODUCTOS_SP (select con joins)
	CONSULTAR_PRODUCTOS_MARCA_SP (select con join, marcas)
	CONSULTAR_PRODUCTOS_TIPO_SP (Select con join tipos)
	CONSULTAR_PRODUCTOS_PROVEEDORES_SP (Select con join proveedores)
	REGISTRAR_NUEVO_PRODUCTO_SP (Incluye Tipo, Marca, Proveedor y descuento null porque apenas se crea el producto, se busca en inventario y en ubicación y 
								se aumenta la cantidad del producto para el inventario de esa ubicación en específico, si no existe 
								se agrega a inventario y se le pone la cantidad agregada al registro)
	MODIFICAR_PRODUCTO_SP (UPDATE al tipo, marca, proveedor, y datos generales del producto, no aplica update al descuento)
	CAMBIAR_ESTADO_PRODUCTO_SP (Activo o inactivo, se debe aplicar el estado en inventario también) 

	CONSULTAR_ESTADOS_ENTREGA_SP (Select simple estados_entrega)
	REGISTRAR_ESTADO_ENTREGA_SP (Insert estados_entrega)
	CAMBIAR_ESTADO_DE_ESTADO_ENTREGA_SP (Activar o Inactivar)
	MODIFICAR_ESTADO_ENTREGA_SP (Update estados_entrega)

	FACTURAR_CLIENTE_SP (crear encabezados, referenciar cliente, agregar entrega si aplica y referenciar el estado y detallar factura, 
						agregar productos, verificar descuentos, aplicar descuentos si existen, 
						agregar cantidad compra al tipo de cliente, verificar suma de montos, aplicar impuestos)
*/