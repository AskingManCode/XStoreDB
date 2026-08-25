USE XSTORE;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Productos_Insertar
    @NombreUsuario   VARCHAR(75),
    @RutaImagen      VARCHAR(275),
    @Descripcion     VARCHAR(150),
    @TipoProducto    VARCHAR(75),
    @MarcaProducto   VARCHAR(75),
    @NombreProveedor VARCHAR(150),
    @PrecioCompra    DECIMAL(10, 2),
    @PrecioVenta     DECIMAL(10, 2),
    @NombreUbicacion VARCHAR(75),
    @CantidadIngreso INT,
    @StockMinimo     INT,
    @NombreDescuento VARCHAR(100) = NULL,
    @ConfirmarPrecioMenor BIT = 0
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @PersonaId INT;
    DECLARE @TipoProductoId INT;
    DECLARE @MarcaId INT;
    DECLARE @ProveedorId INT;
    DECLARE @ProductoId INT;
    DECLARE @UbicacionId INT;
    DECLARE @DescuentoId INT;

    SELECT @PersonaId = S.SESION_PER_ID
    FROM dbo.SESIONES_TB AS S
    INNER JOIN dbo.ROLES_TB AS R ON R.ROL_ID = S.SESION_ROL_ID
    WHERE S.SESION_NombreUsuario = @NombreUsuario
      AND S.SESION_Estado = 1
      AND R.ROL_Nombre = 'Administrador';

    SET @RutaImagen = TRIM(ISNULL(@RutaImagen, ''));
    SET @Descripcion = TRIM(ISNULL(@Descripcion, ''));
    SET @TipoProducto = TRIM(ISNULL(@TipoProducto, ''));
    SET @MarcaProducto = TRIM(ISNULL(@MarcaProducto, ''));
    SET @NombreProveedor = TRIM(ISNULL(@NombreProveedor, ''));
    SET @NombreUbicacion = TRIM(ISNULL(@NombreUbicacion, ''));
    SET @NombreDescuento = NULLIF(TRIM(@NombreDescuento), '');

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @PersonaId IS NULL
            THROW 50000, N'Acceso denegado: El usuario no tiene permisos.', 1;

        IF LEN(@RutaImagen) = 0
            OR LEN(@Descripcion) = 0
            OR LEN(@TipoProducto) = 0
            OR LEN(@MarcaProducto) = 0
            OR LEN(@NombreProveedor) = 0
            OR LEN(@NombreUbicacion) = 0
            OR @PrecioVenta IS NULL
        BEGIN
            THROW 50001, N'Debe completar los campos obligatorios.', 1;
        END;

        IF @PrecioCompra IS NULL OR @PrecioCompra < 0
            THROW 50002, N'El precio de compra no puede ser negativo.', 1;

        IF @PrecioVenta <= 0
            THROW 50003, N'El precio de venta debe ser mayor a 0.', 1;

        IF @PrecioVenta < @PrecioCompra AND @ConfirmarPrecioMenor = 0
            THROW 50004, N'El precio de venta es menor al precio de compra. ¿Desea continuar?', 1;

        IF @CantidadIngreso <= 0 OR @StockMinimo < 0
            THROW 50005, N'La cantidad y la existencia mínima deben ser válidas.', 1;

        SELECT @TipoProductoId = TIPO_PRD_ID
        FROM dbo.TIPOS_PRODUCTOS_TB
        WHERE TIPO_PRD_Nombre = @TipoProducto
          AND TIPO_PRD_Estado = 1;

        SELECT @MarcaId = MARC_PRD_ID
        FROM dbo.MARCAS_PRODUCTOS_TB
        WHERE MARC_PRD_Nombre = @MarcaProducto
          AND MARC_PRD_Estado = 1;

        SELECT @ProveedorId = PRV.PRV_ID
        FROM dbo.PROVEEDORES_TB AS PRV
        INNER JOIN dbo.PERSONAS_TB AS P ON P.PER_ID = PRV.PRV_PER_ID
        WHERE P.PER_NombreCompleto = @NombreProveedor
          AND P.PER_Estado = 1
          AND PRV.PRV_Estado = 1;

        SELECT @UbicacionId = UBI_INV_ID
        FROM dbo.UBI_INVENTARIOS_TB
        WHERE UBI_INV_Nombre = @NombreUbicacion
          AND UBI_INV_Estado = 1;

        IF @TipoProductoId IS NULL OR @MarcaId IS NULL
            OR @ProveedorId IS NULL OR @UbicacionId IS NULL
            THROW 50006, N'Uno de los datos relacionados no existe o está inactivo.', 1;

        IF @NombreDescuento IS NOT NULL
        BEGIN
            SELECT @DescuentoId = DESC_ID
            FROM dbo.DESCUENTOS_TB
            WHERE DESC_NombreComercial = @NombreDescuento
              AND DESC_Estado = 1
              AND CAST(GETDATE() AS DATE) <= DESC_FechaFin;

            IF @DescuentoId IS NULL
                THROW 50007, N'El descuento no existe, está inactivo o no está vigente.', 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM dbo.PRODUCTOS_TB AS P
            INNER JOIN dbo.INVENTARIOS_TB AS I ON I.INV_PRD_ID = P.PRD_ID
            WHERE P.PRD_Descripcion = @Descripcion
              AND I.INV_UBI_INV_ID = @UbicacionId
        )
            THROW 50008, N'Ya existe un producto con ese código.', 1;

        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', @PersonaId;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', 'sp_Productos_Insertar';

        INSERT INTO dbo.PRODUCTOS_TB (
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
            @TipoProductoId,
            @MarcaId,
            @ProveedorId,
            @DescuentoId,
            @PrecioCompra,
            @PrecioVenta
        );

        SET @ProductoId = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.INVENTARIOS_TB (
            INV_UBI_INV_ID,
            INV_PRD_ID,
            INV_StockMinimo,
            INV_StockActual
        )
        VALUES (@UbicacionId, @ProductoId, @StockMinimo, @CantidadIngreso);

        COMMIT;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', NULL;

        SELECT @ProductoId AS PRD_ID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', NULL;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Productos_Actualizar
    @NombreUsuario      VARCHAR(75),
    @ProductoId         INT,
    @RutaImagen         VARCHAR(275) = NULL,
    @Descripcion        VARCHAR(150) = NULL,
    @TipoProducto       VARCHAR(75) = NULL,
    @MarcaProducto      VARCHAR(75) = NULL,
    @NombreProveedor    VARCHAR(150) = NULL,
    @PrecioCompra       DECIMAL(10, 2) = NULL,
    @PrecioVenta        DECIMAL(10, 2) = NULL,
    @NombreDescuento    VARCHAR(100) = NULL,
    @NombreUbicacion    VARCHAR(75) = NULL,
    @StockMinimo        INT = NULL,
    @AjusteStock        INT = NULL,
    @ConfirmarPrecioMenor BIT = 0
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @PersonaId INT;
    DECLARE @TipoProductoId INT;
    DECLARE @MarcaId INT;
    DECLARE @ProveedorId INT;
    DECLARE @DescuentoId INT;
    DECLARE @UbicacionId INT;
    DECLARE @InventarioId INT;
    DECLARE @PrecioCompraFinal DECIMAL(10, 2);
    DECLARE @PrecioVentaFinal DECIMAL(10, 2);

    SELECT @PersonaId = S.SESION_PER_ID
    FROM dbo.SESIONES_TB AS S
    INNER JOIN dbo.ROLES_TB AS R ON R.ROL_ID = S.SESION_ROL_ID
    WHERE S.SESION_NombreUsuario = @NombreUsuario
      AND S.SESION_Estado = 1
      AND R.ROL_Nombre = 'Administrador';

    SET @Descripcion = NULLIF(TRIM(@Descripcion), '');
    SET @RutaImagen = NULLIF(TRIM(@RutaImagen), '');
    SET @NombreUbicacion = NULLIF(TRIM(@NombreUbicacion), '');

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @PersonaId IS NULL
            THROW 50010, N'Acceso denegado: El usuario no tiene permisos.', 1;

        SELECT
            @PrecioCompraFinal = ISNULL(@PrecioCompra, PRD_PrecioCompra),
            @PrecioVentaFinal = ISNULL(@PrecioVenta, PRD_PrecioVenta)
        FROM dbo.PRODUCTOS_TB
        WHERE PRD_ID = @ProductoId;

        IF @PrecioCompraFinal IS NULL
            THROW 50011, N'El producto no existe.', 1;

        IF @PrecioVentaFinal < @PrecioCompraFinal AND @ConfirmarPrecioMenor = 0
            THROW 50012, N'El precio de venta es menor al precio de compra. ¿Desea continuar?', 1;

        IF @TipoProducto IS NOT NULL
        BEGIN
            SELECT @TipoProductoId = TIPO_PRD_ID
            FROM dbo.TIPOS_PRODUCTOS_TB
            WHERE TIPO_PRD_Nombre = TRIM(@TipoProducto)
              AND TIPO_PRD_Estado = 1;

            IF @TipoProductoId IS NULL
                THROW 50015, N'El tipo de producto no existe o está inactivo.', 1;
        END;

        IF @MarcaProducto IS NOT NULL
        BEGIN
            SELECT @MarcaId = MARC_PRD_ID
            FROM dbo.MARCAS_PRODUCTOS_TB
            WHERE MARC_PRD_Nombre = TRIM(@MarcaProducto)
              AND MARC_PRD_Estado = 1;

            IF @MarcaId IS NULL
                THROW 50016, N'La marca no existe o está inactiva.', 1;
        END;

        IF @NombreProveedor IS NOT NULL
        BEGIN
            SELECT @ProveedorId = PRV.PRV_ID
            FROM dbo.PROVEEDORES_TB AS PRV
            INNER JOIN dbo.PERSONAS_TB AS P ON P.PER_ID = PRV.PRV_PER_ID
            WHERE P.PER_NombreCompleto = TRIM(@NombreProveedor)
              AND P.PER_Estado = 1
              AND PRV.PRV_Estado = 1;

            IF @ProveedorId IS NULL
                THROW 50017, N'El proveedor no existe o está inactivo.', 1;
        END;

        IF @NombreDescuento IS NOT NULL
        BEGIN
            SELECT @DescuentoId = DESC_ID
            FROM dbo.DESCUENTOS_TB
            WHERE DESC_NombreComercial = NULLIF(TRIM(@NombreDescuento), '')
              AND DESC_Estado = 1
              AND CAST(GETDATE() AS DATE) <= DESC_FechaFin;

            IF @DescuentoId IS NULL
                THROW 50018, N'El descuento no existe, está inactivo o no está vigente.', 1;
        END;

        IF @NombreUbicacion IS NOT NULL
        BEGIN
            SELECT @UbicacionId = UBI_INV_ID
            FROM dbo.UBI_INVENTARIOS_TB
            WHERE UBI_INV_Nombre = @NombreUbicacion
              AND UBI_INV_Estado = 1;

            SELECT @InventarioId = INV_ID
            FROM dbo.INVENTARIOS_TB
            WHERE INV_PRD_ID = @ProductoId
              AND INV_UBI_INV_ID = @UbicacionId;

            IF @UbicacionId IS NULL OR @InventarioId IS NULL
                THROW 50013, N'La ubicación del inventario no existe o no está asociada al producto.', 1;
        END;

        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', @PersonaId;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', 'sp_Productos_Actualizar';

        UPDATE dbo.PRODUCTOS_TB
        SET PRD_RutaImagen = ISNULL(@RutaImagen, PRD_RutaImagen),
            PRD_Descripcion = ISNULL(@Descripcion, PRD_Descripcion),
            PRD_TIPO_PRD_ID = ISNULL(@TipoProductoId, PRD_TIPO_PRD_ID),
            PRD_MARC_PRD_ID = ISNULL(@MarcaId, PRD_MARC_PRD_ID),
            PRD_PRV_ID = ISNULL(@ProveedorId, PRD_PRV_ID),
            PRD_DESC_ID = ISNULL(@DescuentoId, PRD_DESC_ID),
            PRD_PrecioCompra = ISNULL(@PrecioCompra, PRD_PrecioCompra),
            PRD_PrecioVenta = ISNULL(@PrecioVenta, PRD_PrecioVenta)
        WHERE PRD_ID = @ProductoId;

        IF @NombreUbicacion IS NOT NULL
        BEGIN
            UPDATE dbo.INVENTARIOS_TB
            SET INV_StockMinimo = ISNULL(@StockMinimo, INV_StockMinimo),
                INV_StockActual = INV_StockActual + ISNULL(@AjusteStock, 0)
            WHERE INV_ID = @InventarioId
              AND INV_StockActual + ISNULL(@AjusteStock, 0) >= 0;

            IF @@ROWCOUNT = 0
                THROW 50014, N'El ajuste dejaría la existencia en un valor inválido.', 1;
        END;

        COMMIT;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', NULL;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', NULL;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Productos_CambiarEstado
    @NombreUsuario VARCHAR(75),
    @ProductoId INT,
    @Estado BIT
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    DECLARE @PersonaId INT;

    SELECT @PersonaId = S.SESION_PER_ID
    FROM dbo.SESIONES_TB AS S
    INNER JOIN dbo.ROLES_TB AS R ON R.ROL_ID = S.SESION_ROL_ID
    WHERE S.SESION_NombreUsuario = @NombreUsuario
      AND S.SESION_Estado = 1
      AND R.ROL_Nombre = 'Administrador';

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @PersonaId IS NULL
            THROW 50020, N'Acceso denegado: El usuario no tiene permisos.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.PRODUCTOS_TB WHERE PRD_ID = @ProductoId)
            THROW 50021, N'El producto no existe.', 1;

        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', @PersonaId;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', 'sp_Productos_CambiarEstado';

        UPDATE dbo.PRODUCTOS_TB
        SET PRD_Estado = @Estado
        WHERE PRD_ID = @ProductoId;

        UPDATE dbo.INVENTARIOS_TB
        SET INV_Estado = @Estado
        WHERE INV_PRD_ID = @ProductoId;

        COMMIT;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', NULL;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'PERSONA_ID', NULL;
        EXEC dbo.SP_SET_SESSION_CONTEXT 'ORIGEN', NULL;
        THROW;
    END CATCH;
END;
GO
