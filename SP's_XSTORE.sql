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
		FROM PERSONAS_TB
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



/*
	SP's XStore

	REGISTRAR_AUDITORIA_SP (Parámetros - Persona_id, accion[insert, delete, update], tablaAfectada, Descripción[mas de 10 letras])
	CONSULTA_AUDITORIAS_SP (Select y join de todas las auditorias con nombre de persona y su nombre de usuario)

	CONSULTAR_ROLES_SP (Select simple Roles)
	REGISTRAR_ROL_SP (Insert a Roles)
	MODIFICAR_ROL_SP (Update a Roles)
	CAMBIAR_ESTADO_ROL_SP (Activar o Inactivar Rol)

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