USE SmartPlate;
DELIMITER $$

-- =================================================
-- TRIGGER 1: AFTER INSERT ON Menu_Orders_Items
-- Deduct ingredients FIFO from status=2 batches
-- Delete batch if quantity hits 0
-- Log each deduction
-- Alert all chef/kitchen staff
-- NOTE: Sales_History logged on DELIVERY (status->2) not here
-- =================================================
CREATE TRIGGER trg_after_order_item
AFTER INSERT ON Menu_Orders_Items
FOR EACH ROW
BEGIN
    DECLARE done       INT DEFAULT 0;
    DECLARE ing_id     INT;
    DECLARE recipe_qty DECIMAL(6,2);
    DECLARE remaining  DECIMAL(6,2);
    DECLARE batch_id   INT;
    DECLARE batch_qty  DECIMAL(6,2);
    DECLARE deduct     DECIMAL(6,2);
    DECLARE new_qty    DECIMAL(6,2);
    DECLARE v_alert_id INT;
    DECLARE v_uid      INT;
    DECLARE chef_done  INT DEFAULT 0;
    DECLARE v_shortfall INT DEFAULT 0;

    DECLARE ing_cur CURSOR FOR
        SELECT ingredient_id, quantity FROM Recipes WHERE item_id = NEW.item_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- Availability check: abort if any ingredient lacks sufficient stock (C2)
    SELECT COUNT(*) INTO v_shortfall
    FROM Recipes r
    JOIN Ingredients i ON i.ingredient_id = r.ingredient_id
    WHERE r.item_id = NEW.item_id
      AND i.quantity < r.quantity * NEW.quantity;

    IF v_shortfall > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient ingredient stock to fulfill this order item';
    END IF;

    OPEN ing_cur;
    ing_loop: LOOP
        FETCH ing_cur INTO ing_id, recipe_qty;
        IF done THEN LEAVE ing_loop; END IF;

        SET remaining = recipe_qty * NEW.quantity;
        UPDATE Ingredients SET quantity = quantity - remaining
        WHERE ingredient_id = ing_id;

        batch_loop: WHILE remaining > 0 DO
            SET batch_id = NULL;
            SELECT inventory_batch_id, quantity INTO batch_id, batch_qty
            FROM Inventory_Batches
            WHERE ingredient_id = ing_id AND status = 2 AND quantity > 0
            ORDER BY expiry_date ASC LIMIT 1;

            IF batch_id IS NULL THEN LEAVE batch_loop; END IF;

            SET deduct = IF(batch_qty >= remaining, remaining, batch_qty);
            SET new_qty = batch_qty - deduct;

            IF new_qty <= 0 THEN
                DELETE FROM Inventory_Batches WHERE inventory_batch_id = batch_id;
            ELSE
                UPDATE Inventory_Batches SET quantity = new_qty WHERE inventory_batch_id = batch_id;
            END IF;

            INSERT INTO Logs (timestamp, quantity, status, ingredient_id)
            VALUES (NOW(), deduct, 1, ing_id);

            SET remaining = remaining - deduct;
        END WHILE batch_loop;
    END LOOP ing_loop;
    CLOSE ing_cur;

    INSERT INTO Alerts (message)
    VALUES (CONCAT('New order #', NEW.menu_order_id, ': ', NEW.item_id, ' x', NEW.quantity));
    SET v_alert_id = LAST_INSERT_ID();

    BEGIN
        DECLARE chef_cur CURSOR FOR
            SELECT u.user_id FROM Users u
            INNER JOIN Roles r ON u.role_id = r.role_id
            INNER JOIN Employees e ON e.user_id = u.user_id
            WHERE LOWER(r.name) IN ('chef', 'kitchen');
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET chef_done = 1;
        OPEN chef_cur;
        chef_loop: LOOP
            FETCH chef_cur INTO v_uid;
            IF chef_done THEN LEAVE chef_loop; END IF;
            INSERT INTO Alerted (alert_id, user_id, created_at) VALUES (v_alert_id, v_uid, NOW());
        END LOOP chef_loop;
        CLOSE chef_cur;
    END;
END$$


-- =================================================
-- TRIGGER 2: AFTER UPDATE ON Inventory_Batches
-- status -> 2: add quantity to Ingredients + log
-- =================================================
CREATE TRIGGER trg_after_batch_delivered
AFTER UPDATE ON Inventory_Batches
FOR EACH ROW
BEGIN
    IF OLD.status <> 2 AND NEW.status = 2 THEN
        UPDATE Ingredients SET quantity = quantity + NEW.quantity
        WHERE ingredient_id = NEW.ingredient_id;
        INSERT INTO Logs (timestamp, quantity, status, ingredient_id)
        VALUES (NOW(), NEW.quantity, 0, NEW.ingredient_id);
    END IF;
END$$


-- =================================================
-- TRIGGER 3: AFTER UPDATE ON Ingredients
-- Whenever quantity sits at/below min_stock and no
-- pending batch exists -> auto-order from the supplier
-- with the smallest delivery_time. The v_pending guard
-- dedupes so repeated updates don't stack orders.
-- =================================================
CREATE TRIGGER trg_after_ingredient_update
AFTER UPDATE ON Ingredients
FOR EACH ROW
BEGIN
    DECLARE v_supplier_id    INT;
    DECLARE v_pending        INT;
    DECLARE v_price_per_unit DECIMAL(10,2);
    DECLARE v_order_qty      DECIMAL(6,2);

    IF NEW.quantity <= NEW.min_stock THEN
        SELECT COUNT(*) INTO v_pending
        FROM Inventory_Batches
        WHERE ingredient_id = NEW.ingredient_id AND status IN (0, 1);

        IF v_pending = 0 THEN
            SELECT s.supplier_id, sp.price_per_unit
              INTO v_supplier_id, v_price_per_unit
            FROM Suppliers s
            INNER JOIN Supplies sp ON s.supplier_id = sp.supplier_id
            WHERE sp.ingredient_id = NEW.ingredient_id AND s.is_active = 1
            ORDER BY s.delivery_time ASC LIMIT 1;

            IF v_supplier_id IS NOT NULL THEN
                -- Reorder enough to bring stock to ~2x min_stock so delivery
                -- actually restocks the ingredient (see C1)
                SET v_order_qty = GREATEST(NEW.min_stock * 2, 1);
                INSERT INTO Inventory_Batches
                    (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
                VALUES (NOW(), NULL, v_order_qty, NEW.unit,
                        v_order_qty * COALESCE(v_price_per_unit, 0),
                        0, v_supplier_id, NEW.ingredient_id);
            END IF;
        END IF;
    END IF;
END$$


-- =================================================
-- TRIGGER 4: AFTER INSERT ON Ingredients
-- If an active supplier exists and min_stock > 0,
-- place an auto-order (quantity starts at 0 <= min_stock).
-- If no supplier supplies it, alert managers so they
-- can onboard one (paired with trg_after_supplies_insert)
-- =================================================
CREATE TRIGGER trg_after_ingredient_insert
AFTER INSERT ON Ingredients
FOR EACH ROW
BEGIN
    DECLARE v_supplier_id    INT DEFAULT NULL;
    DECLARE v_alert_id       INT;
    DECLARE v_price_per_unit DECIMAL(10,2);
    DECLARE v_order_qty      DECIMAL(6,2);

    SELECT s.supplier_id, sp.price_per_unit
      INTO v_supplier_id, v_price_per_unit
    FROM Suppliers s
    INNER JOIN Supplies sp ON s.supplier_id = sp.supplier_id
    WHERE sp.ingredient_id = NEW.ingredient_id AND s.is_active = 1
    ORDER BY s.delivery_time ASC LIMIT 1;

    IF v_supplier_id IS NULL THEN
        INSERT INTO Alerts (message)
        VALUES (LEFT(CONCAT('No supplier available for new ingredient: ', NEW.name), 150));
        SET v_alert_id = LAST_INSERT_ID();

        INSERT INTO Alerted (alert_id, user_id, created_at)
        SELECT v_alert_id, u.user_id, NOW()
        FROM Users u
        INNER JOIN Roles r ON u.role_id = r.role_id
        WHERE LOWER(r.name) = 'manager';
    ELSEIF NEW.min_stock > 0 THEN
        -- Reorder enough to bring stock to ~2x min_stock (see C1)
        SET v_order_qty = GREATEST(NEW.min_stock * 2, 1);
        INSERT INTO Inventory_Batches
            (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
        VALUES (NOW(), NULL, v_order_qty, NEW.unit,
                v_order_qty * COALESCE(v_price_per_unit, 0),
                0, v_supplier_id, NEW.ingredient_id);
    END IF;
END$$


-- =================================================
-- TRIGGER 4b: AFTER INSERT ON Supplies
-- First supplier for an ingredient -> alert managers
-- that a supplier has been found. Subsequent suppliers
-- are a no-op (the "found" signal already fired).
-- =================================================
CREATE TRIGGER trg_after_supplies_insert
AFTER INSERT ON Supplies
FOR EACH ROW
BEGIN
    DECLARE v_supplier_count INT;
    DECLARE v_alert_id       INT;
    DECLARE v_ing_name       VARCHAR(100);
    DECLARE v_sup_name       VARCHAR(100);

    SELECT COUNT(*) INTO v_supplier_count
    FROM Supplies
    WHERE ingredient_id = NEW.ingredient_id;

    IF v_supplier_count = 1 THEN
        SELECT name INTO v_ing_name FROM Ingredients WHERE ingredient_id = NEW.ingredient_id;
        SELECT name INTO v_sup_name FROM Suppliers  WHERE supplier_id  = NEW.supplier_id;

        INSERT INTO Alerts (message)
        VALUES (LEFT(CONCAT('Supplier found for ', v_ing_name, ': ', v_sup_name), 150));
        SET v_alert_id = LAST_INSERT_ID();

        INSERT INTO Alerted (alert_id, user_id, created_at)
        SELECT v_alert_id, u.user_id, NOW()
        FROM Users u
        INNER JOIN Roles r ON u.role_id = r.role_id
        WHERE LOWER(r.name) = 'manager';
    END IF;
END$$


-- =================================================
-- TRIGGER 5a: BEFORE UPDATE ON Menu_Orders_Items
-- Guard: no backwards transitions allowed
-- Stamp dispatched_at / delivered_at on the NEW row
-- (must be done here — AFTER triggers cannot UPDATE
-- the same table that invoked them, MySQL error 1442)
-- =================================================
CREATE TRIGGER trg_before_order_item_status
BEFORE UPDATE ON Menu_Orders_Items
FOR EACH ROW
BEGIN
    IF NEW.status < OLD.status THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order item status cannot go backwards';
    END IF;

    IF OLD.status <> 1 AND NEW.status = 1 AND NEW.dispatched_at IS NULL THEN
        SET NEW.dispatched_at = NOW();
    END IF;

    IF OLD.status <> 2 AND NEW.status = 2 AND NEW.delivered_at IS NULL THEN
        SET NEW.delivered_at = NOW();
    END IF;
END$$


-- =================================================
-- TRIGGER 5b: AFTER UPDATE ON Menu_Orders_Items
-- status 0->1: alert customer
-- status 1->2: log to Sales_History
-- =================================================
CREATE TRIGGER trg_after_order_item_status
AFTER UPDATE ON Menu_Orders_Items
FOR EACH ROW
BEGIN
    DECLARE v_alert_id   INT;
    DECLARE v_user_id    INT;
    DECLARE v_occ_id     INT;
    DECLARE v_order_date DATE;

    -- Out for delivery: alert customer
    IF OLD.status <> 1 AND NEW.status = 1 THEN
        SELECT user_id INTO v_user_id FROM Menu_Orders WHERE menu_order_id = NEW.menu_order_id;
        INSERT INTO Alerts (message)
        VALUES (CONCAT('Your order #', NEW.menu_order_id, ' is on the way!'));
        SET v_alert_id = LAST_INSERT_ID();
        INSERT INTO Alerted (alert_id, user_id, created_at) VALUES (v_alert_id, v_user_id, NOW());
    END IF;

    -- Delivered: log to Sales_History
    IF OLD.status <> 2 AND NEW.status = 2 THEN
        SELECT DATE(order_time) INTO v_order_date
        FROM Menu_Orders WHERE menu_order_id = NEW.menu_order_id;

        SELECT occasion_id INTO v_occ_id
        FROM Occasions WHERE `date` = v_order_date LIMIT 1;

        IF v_occ_id IS NULL THEN
            INSERT IGNORE INTO Occasions (name) VALUES ('Regular');
            SELECT occasion_id INTO v_occ_id FROM Occasions WHERE name = 'Regular' LIMIT 1;
        END IF;

        INSERT INTO Sales_History (quantity, item_id, menu_order_id, occasion_id)
        VALUES (NEW.quantity, NEW.item_id, NEW.menu_order_id, v_occ_id);
    END IF;
END$$


-- =================================================
-- TRIGGER 6: AFTER INSERT ON Gift_Code
-- Announce the new code to every customer via the
-- Alerts/Alerted fan-out used by /user/alerts
-- =================================================
CREATE TRIGGER trg_after_gift_code_insert
AFTER INSERT ON Gift_Code
FOR EACH ROW
BEGIN
    DECLARE v_alert_id INT;
    DECLARE v_msg      VARCHAR(150);

    -- Gift_Code.type: 0 = percent-based, 1 = flat amount
    IF NEW.type = 0 THEN
        SET v_msg = CONCAT('New gift code ', NEW.code, ': ',
                           NEW.amount, '% off - valid until ', DATE(NEW.valid_to));
    ELSE
        SET v_msg = CONCAT('New gift code ', NEW.code, ': ',
                           NEW.amount, ' off - valid until ', DATE(NEW.valid_to));
    END IF;

    INSERT INTO Alerts (message) VALUES (v_msg);
    SET v_alert_id = LAST_INSERT_ID();

    INSERT INTO Alerted (alert_id, user_id, created_at)
    SELECT v_alert_id, c.user_id, NOW() FROM Customers c;
END$$


DELIMITER ;
