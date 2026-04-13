USE SmartPlate;
DELIMITER $$

CREATE PROCEDURE sp_AddIngredient(
    IN p_name      VARCHAR(100),
    IN p_unit      VARCHAR(15),
    IN p_min_stock DECIMAL(6,2),
    IN p_allergen  VARCHAR(100)
)
BEGIN
    DECLARE v_allergen_id INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;
    INSERT IGNORE INTO Allergens (name) VALUES (p_allergen);
    SELECT allergen_id INTO v_allergen_id FROM Allergens WHERE name = p_allergen LIMIT 1;
    -- Insert with quantity=0; trg_after_ingredient_insert will auto-order if supplier exists
    INSERT INTO Ingredients (name, unit, min_stock, quantity, allergen_id)
    VALUES (p_name, p_unit, p_min_stock, 0, v_allergen_id);
    COMMIT;
END $$


-- Employee orders a new batch; cost = quantity * price_per_unit from Supplies
CREATE PROCEDURE sp_ReceiveBatch(
    IN p_ingredient_id INT,
    IN p_supplier_id   INT,
    IN p_quantity      DECIMAL(6,2)
)
BEGIN
    DECLARE v_price_per_unit DECIMAL(10,2);
    DECLARE v_unit           VARCHAR(15);

    SELECT price_per_unit, unit INTO v_price_per_unit, v_unit
    FROM Supplies
    WHERE supplier_id = p_supplier_id AND ingredient_id = p_ingredient_id
    LIMIT 1;

    INSERT INTO Inventory_Batches
        (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
    VALUES
        (NOW(), NULL, p_quantity, v_unit,
         p_quantity * COALESCE(v_price_per_unit, 0), 0, p_supplier_id, p_ingredient_id);
END $$


-- Log waste - validates batch exists and quantity doesn't exceed batch quantity
CREATE PROCEDURE sp_LogWaste(
    IN p_batch_id INT,
    IN p_quantity DECIMAL(6,2)
)
BEGIN
    DECLARE v_ingredient_id INT;
    DECLARE v_batch_qty     DECIMAL(6,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    -- Validate batch exists
    SELECT ingredient_id, quantity INTO v_ingredient_id, v_batch_qty
    FROM Inventory_Batches WHERE inventory_batch_id = p_batch_id;

    IF v_ingredient_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Batch not found';
    END IF;

    IF p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Waste quantity must be greater than zero';
    END IF;

    IF p_quantity > v_batch_qty THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Waste quantity cannot exceed batch quantity';
    END IF;

    START TRANSACTION;

    INSERT INTO Waste_Records (quantity, timestamp, inventory_batch_id)
    VALUES (p_quantity, NOW(), p_batch_id);

    INSERT INTO Logs (timestamp, quantity, status, ingredient_id)
    VALUES (NOW(), p_quantity, 2, v_ingredient_id);

    UPDATE Ingredients
    SET quantity = GREATEST(0, quantity - p_quantity)
    WHERE ingredient_id = v_ingredient_id;

    UPDATE Inventory_Batches
    SET quantity = GREATEST(0, quantity - p_quantity)
    WHERE inventory_batch_id = p_batch_id;

    COMMIT;
END $$


CREATE PROCEDURE sp_AddMenuItem(
    IN p_name        VARCHAR(100),
    IN p_description VARCHAR(100),
    IN p_price       DECIMAL(10,2),
    IN p_prep_time   INT,
    IN p_category    VARCHAR(100)
)
BEGIN
    DECLARE v_category_id INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;
    INSERT IGNORE INTO Category (name) VALUES (p_category);
    SELECT category_id INTO v_category_id FROM Category WHERE name = p_category LIMIT 1;
    INSERT INTO Items (name, description, price, prep_time, is_active, category_id)
    VALUES (p_name, p_description, p_price, p_prep_time, 1, v_category_id);
    COMMIT;
END $$


CREATE PROCEDURE sp_AddRecipeLine(
    IN p_item_id       INT,
    IN p_ingredient_id INT,
    IN p_quantity      DECIMAL(6,2),
    IN p_unit          VARCHAR(15)
)
BEGIN
    INSERT INTO Recipes (item_id, ingredient_id, quantity, unit)
    VALUES (p_item_id, p_ingredient_id, p_quantity, p_unit)
    ON DUPLICATE KEY UPDATE quantity = p_quantity, unit = p_unit;
END $$


-- Registers any user type including supplier
-- For supplier type: also creates Suppliers row linked to user_id
CREATE PROCEDURE sp_RegisterUser(
    IN p_username     VARCHAR(100),
    IN p_email        VARCHAR(100),
    IN p_pwd_hash     VARCHAR(255),
    IN p_role_name    VARCHAR(100),
    IN p_user_type    VARCHAR(20),
    IN p_name         VARCHAR(100),
    IN p_salary       DECIMAL(15,2),
    IN p_contact      VARCHAR(100),
    IN p_delivery_time INT
)
BEGIN
    DECLARE v_role_id INT;
    DECLARE v_user_id INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    -- Whitelist the role name (S5)
    IF p_role_name NOT IN ('manager','chef','employee','supplier','customer') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid role name';
    END IF;

    SELECT role_id INTO v_role_id FROM Roles WHERE name = p_role_name LIMIT 1;
    IF v_role_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Role not found - seed Roles table before registering users';
    END IF;

    START TRANSACTION;

    INSERT INTO Users (username, email, password_hash, last_login, role_id)
    VALUES (p_username, p_email, p_pwd_hash, NOW(), v_role_id);
    SET v_user_id = LAST_INSERT_ID();

    IF p_user_type = 'customer' THEN
        INSERT INTO Customers (name, visit_frequency, user_id) VALUES (p_name, 0, v_user_id);
    ELSEIF p_user_type = 'employee' OR p_user_type = 'chef' OR p_user_type = 'kitchen' THEN
        INSERT INTO Employees (hire_date, salary, user_id) VALUES (NOW(), p_salary, v_user_id);
    ELSEIF p_user_type = 'supplier' THEN
        INSERT INTO Suppliers (name, contact, delivery_time, is_active, user_id)
        VALUES (p_name, COALESCE(p_contact,''), COALESCE(p_delivery_time,1), 1, v_user_id);
    END IF;

    COMMIT;
END $$


CREATE PROCEDURE sp_PlaceOrder(IN p_user_id INT)
BEGIN
    INSERT INTO Menu_Orders (order_time, price, user_id) VALUES (NOW(), 0, p_user_id);
    SELECT LAST_INSERT_ID() AS order_id;
END$$


CREATE PROCEDURE sp_AddOrderItem(
    IN p_order_id INT,
    IN p_item_id  INT,
    IN p_quantity DECIMAL(6,2)
)
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    IF p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be > 0';
    END IF;

    SELECT price INTO v_price FROM Items WHERE item_id = p_item_id AND is_active = 1;
    IF v_price IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item not found or not active';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Recipes WHERE item_id = p_item_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item has no recipe and cannot be ordered';
    END IF;

    START TRANSACTION;
    INSERT INTO Menu_Orders_Items (menu_order_id, item_id, quantity, status, prepared_at)
    VALUES (p_order_id, p_item_id, p_quantity, 0, NOW());
    UPDATE Menu_Orders SET price = price + (v_price * p_quantity)
    WHERE menu_order_id = p_order_id;
    COMMIT;
END $$


-- Cancel an order item: re-credit ingredients back to stock (C3)
-- Only callable while item status = 0 (being prepared)
CREATE PROCEDURE sp_CancelOrderItem(
    IN p_order_id INT,
    IN p_item_id  INT
)
BEGIN
    DECLARE v_status   TINYINT;
    DECLARE v_qty      DECIMAL(6,2);
    DECLARE done       INT DEFAULT 0;
    DECLARE ing_id     INT;
    DECLARE recipe_qty DECIMAL(6,2);

    DECLARE ing_cur CURSOR FOR
        SELECT ingredient_id, quantity FROM Recipes WHERE item_id = p_item_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    SELECT status, quantity INTO v_status, v_qty
    FROM Menu_Orders_Items
    WHERE menu_order_id = p_order_id AND item_id = p_item_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order item not found';
    END IF;

    IF v_status <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot cancel item already out for delivery';
    END IF;

    START TRANSACTION;

    OPEN ing_cur;
    ing_loop: LOOP
        FETCH ing_cur INTO ing_id, recipe_qty;
        IF done THEN LEAVE ing_loop; END IF;
        UPDATE Ingredients SET quantity = quantity + (recipe_qty * v_qty)
        WHERE ingredient_id = ing_id;
    END LOOP ing_loop;
    CLOSE ing_cur;

    DELETE FROM Menu_Orders_Items
    WHERE menu_order_id = p_order_id AND item_id = p_item_id;

    UPDATE Menu_Orders SET price = (
        SELECT COALESCE(SUM(i.price * oi.quantity), 0)
        FROM Menu_Orders_Items oi JOIN Items i ON oi.item_id = i.item_id
        WHERE oi.menu_order_id = p_order_id
    )
    WHERE menu_order_id = p_order_id;

    COMMIT;
END $$


CREATE PROCEDURE sp_LogCompliance(IN p_status TINYINT, IN p_description VARCHAR(100))
BEGIN
    INSERT INTO Compliance_Records (inspection_date, status, description)
    VALUES (NOW(), p_status, p_description);
END $$


CREATE PROCEDURE sp_RecordWeather(
    IN p_date        DATE,
    IN p_temperature DECIMAL(4,2),
    IN p_humidity    DECIMAL(5,2)
)
BEGIN
    INSERT INTO Weather_Data (date, temperature, humidity)
    VALUES (p_date, p_temperature, p_humidity)
    ON DUPLICATE KEY UPDATE temperature = p_temperature, humidity = p_humidity;
END $$


DELIMITER ;
