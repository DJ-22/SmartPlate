USE mydb;
DELIMITER $$

-- add an ingredient
CREATE PROCEDURE sp_AddIngredient(
    IN p_name      VARCHAR(100),
    IN p_unit      VARCHAR(15),
    IN p_min_stock DECIMAL(6,2),
    IN p_allergen  VARCHAR(100)
)
BEGIN
    DECLARE v_allergen_id INT;

    -- insert allergen if it doesn't exist
    INSERT IGNORE INTO Allergens (name) VALUES (p_allergen);
    SELECT allergen_id INTO v_allergen_id FROM Allergens WHERE name = p_allergen LIMIT 1;

    INSERT INTO Ingredients (name, unit, min_stock, quantity, allergen_id)
    VALUES (p_name, p_unit, p_min_stock, 0, v_allergen_id);
END $$


-- receive a stock batch
CREATE PROCEDURE sp_ReceiveBatch(
    IN p_ingredient_id INT,
    IN p_supplier_id   INT,
    IN p_quantity      DECIMAL(6,2),
    IN p_unit          VARCHAR(15),
    IN p_cost          DECIMAL(10,2),
    IN p_expiry_date   DATETIME
)
BEGIN
    INSERT INTO Inventory_Batches
        (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
    VALUES (NOW(), p_expiry_date, p_quantity, p_unit, p_cost, 1, p_supplier_id, p_ingredient_id);

    -- update ingredient running total
    UPDATE Ingredients SET quantity = quantity + p_quantity
    WHERE ingredient_id = p_ingredient_id;
END $$


-- log a waste event
CREATE PROCEDURE sp_LogWaste(
    IN p_batch_id INT,
    IN p_quantity DECIMAL(6,2)
)
BEGIN
    DECLARE v_ingredient_id INT;
    SELECT ingredient_id INTO v_ingredient_id FROM Inventory_Batches
    WHERE inventory_batch_id = p_batch_id;

    INSERT INTO Waste_Records (quantity, timestamp, inventory_batch_id)
    VALUES (p_quantity, NOW(), p_batch_id);

    UPDATE Ingredients SET quantity = GREATEST(0, quantity - p_quantity)
    WHERE ingredient_id = v_ingredient_id;
END $$


-- add a menu item
CREATE PROCEDURE sp_AddMenuItem(
    IN p_name        VARCHAR(100),
    IN p_description VARCHAR(100),
    IN p_price       DECIMAL(6,2),
    IN p_prep_time   INT,
    IN p_category    VARCHAR(100)
)
BEGIN
    DECLARE v_category_id INT;

    INSERT IGNORE INTO Category (name) VALUES (p_category);
    SELECT category_id INTO v_category_id FROM Category WHERE name = p_category LIMIT 1;

    INSERT INTO Items (name, description, price, prep_time, is_available, category_id)
    VALUES (p_name, p_description, p_price, p_prep_time, 1, v_category_id);
END $$


-- add a recipe line (ingredient -> item)
CREATE PROCEDURE sp_AddRecipeLine(
    IN p_item_id       INT,
    IN p_ingredient_id INT,
    IN p_quantity      DECIMAL(6,2),
    IN p_unit          VARCHAR(15)
)
BEGIN
    INSERT INTO Recipes (item_id, ingredient_id, quantity, unit)
    VALUES (p_item_id, p_ingredient_id, p_quantity, p_unit)
    ON DUPLICATE KEY UPDATE quantity = p_quantity;
END $$


-- register a user (customer or employee)
CREATE PROCEDURE sp_RegisterUser(
    IN p_username  VARCHAR(100),
    IN p_email     VARCHAR(100),
    IN p_pwd_hash  VARCHAR(255),
    IN p_role_name VARCHAR(100),
    IN p_user_type VARCHAR(20),    -- 'customer' or 'employee'
    IN p_name      VARCHAR(100),   -- customer's display name
    IN p_salary    DECIMAL(15,2)   -- pass 0 for customers
)
BEGIN
    DECLARE v_role_id INT;
    DECLARE v_user_id INT;

    INSERT IGNORE INTO Roles (name) VALUES (p_role_name);
    SELECT role_id INTO v_role_id FROM Roles WHERE name = p_role_name LIMIT 1;

    INSERT INTO Users (username, email, password_hash, last_login, role_id)
    VALUES (p_username, p_email, p_pwd_hash, NOW(), v_role_id);

    SET v_user_id = LAST_INSERT_ID();

    IF p_user_type = 'customer' THEN
        INSERT INTO Customers (name, visit_frequency, user_id)
        VALUES (p_name, 0, v_user_id);
    ELSEIF p_user_type = 'employee' THEN
        INSERT INTO Employees (hire_date, salary, user_id)
        VALUES (NOW(), p_salary, v_user_id);
    END IF;
END $$


-- place an order + add items to it
CREATE PROCEDURE sp_PlaceOrder(
    IN p_user_id INT
)
BEGIN
    INSERT INTO Menu_Orders (order_time, price, user_id)
    VALUES (NOW(), 0, p_user_id);
END $$

CREATE PROCEDURE sp_AddOrderItem(
    IN p_order_id INT,
    IN p_item_id  INT,
    IN p_quantity DECIMAL(6,2)
)
BEGIN
    DECLARE v_price DECIMAL(6,2);
    SELECT price INTO v_price FROM Items WHERE item_id = p_item_id;

    INSERT INTO Menu_Orders_Items (menu_order_id, item_id, quantity, status)
    VALUES (p_order_id, p_item_id, p_quantity, 0);

    UPDATE Menu_Orders SET price = price + (v_price * p_quantity)
    WHERE menu_order_id = p_order_id;
END $$


-- record a sale
CREATE PROCEDURE sp_RecordSale(
    IN p_order_id   INT,
    IN p_item_id    INT,
    IN p_quantity   DECIMAL(6,2),
    IN p_occasion   VARCHAR(100)
)
BEGIN
    DECLARE v_occasion_id INT;

    INSERT IGNORE INTO Occasions (name) VALUES (p_occasion);
    SELECT occasion_id INTO v_occasion_id FROM Occasions WHERE name = p_occasion LIMIT 1;

    INSERT INTO Sales_History (quantity, item_id, menu_order_id, occasion_id)
    VALUES (p_quantity, p_item_id, p_order_id, v_occasion_id);
END $$


-- log a compliance inspection
CREATE PROCEDURE sp_LogCompliance(
    IN p_status      TINYINT,      -- 0=failed 1=passed 2=pending
    IN p_description VARCHAR(100)
)
BEGIN
    INSERT INTO Compliance_Records (inspection_date, status, description)
    VALUES (NOW(), p_status, p_description);
END $$


-- record weather data
CREATE PROCEDURE sp_RecordWeather(
    IN p_date        DATETIME,
    IN p_temperature DECIMAL(4,2),
    IN p_humidity    DECIMAL(5,2)
)
BEGIN
    INSERT INTO Weather_Data (date, temperature, humidity)
    VALUES (p_date, p_temperature, p_humidity)
    ON DUPLICATE KEY UPDATE temperature = p_temperature, humidity = p_humidity;
END $$


DELIMITER ;