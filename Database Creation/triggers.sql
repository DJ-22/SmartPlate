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
-- quantity just crossed below min_stock + no pending
-- batch exists -> auto-order from fastest supplier
-- =================================================
CREATE TRIGGER trg_after_ingredient_update
AFTER UPDATE ON Ingredients
FOR EACH ROW
BEGIN
    DECLARE v_supplier_id INT;
    DECLARE v_pending     INT;

    IF NEW.quantity <= NEW.min_stock AND OLD.quantity > NEW.min_stock THEN
        SELECT COUNT(*) INTO v_pending
        FROM Inventory_Batches
        WHERE ingredient_id = NEW.ingredient_id AND status IN (0, 1);

        IF v_pending = 0 THEN
            SELECT s.supplier_id INTO v_supplier_id
            FROM Suppliers s
            INNER JOIN Supplies sp ON s.supplier_id = sp.supplier_id
            WHERE sp.ingredient_id = NEW.ingredient_id AND s.is_active = 1
            ORDER BY s.delivery_time ASC LIMIT 1;

            IF v_supplier_id IS NOT NULL THEN
                -- Reorder enough to bring stock to ~2x min_stock so delivery
                -- actually restocks the ingredient (see C1)
                INSERT INTO Inventory_Batches
                    (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
                VALUES (NOW(), NULL, GREATEST(NEW.min_stock * 2, 1), NEW.unit, NULL, 0, v_supplier_id, NEW.ingredient_id);
            END IF;
        END IF;
    END IF;
END$$


-- =================================================
-- TRIGGER 4: AFTER INSERT ON Ingredients
-- When a new ingredient is added with min_stock > 0,
-- immediately place an auto-order from the fastest
-- active supplier (quantity starts at 0 <= min_stock)
-- =================================================
CREATE TRIGGER trg_after_ingredient_insert
AFTER INSERT ON Ingredients
FOR EACH ROW
BEGIN
    DECLARE v_supplier_id INT;

    IF NEW.min_stock > 0 THEN
        SELECT s.supplier_id INTO v_supplier_id
        FROM Suppliers s
        INNER JOIN Supplies sp ON s.supplier_id = sp.supplier_id
        WHERE sp.ingredient_id = NEW.ingredient_id AND s.is_active = 1
        ORDER BY s.delivery_time ASC LIMIT 1;

        IF v_supplier_id IS NOT NULL THEN
            -- Reorder enough to bring stock to ~2x min_stock (see C1)
            INSERT INTO Inventory_Batches
                (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
            VALUES (NOW(), NULL, GREATEST(NEW.min_stock * 2, 1), NEW.unit, NULL, 0, v_supplier_id, NEW.ingredient_id);
        END IF;
    END IF;
END$$


-- =================================================
-- TRIGGER 5: AFTER UPDATE ON Menu_Orders_Items
-- status 0->1: alert customer
-- status 1->2: log to Sales_History
-- Guard: no backwards transitions allowed
-- =================================================
CREATE TRIGGER trg_after_order_item_status
AFTER UPDATE ON Menu_Orders_Items
FOR EACH ROW
BEGIN
    DECLARE v_alert_id   INT;
    DECLARE v_user_id    INT;
    DECLARE v_occ_id     INT;
    DECLARE v_order_date DATE;

    -- Prevent backwards transitions at trigger level
    IF NEW.status < OLD.status THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order item status cannot go backwards';
    END IF;

    -- Out for delivery: alert customer + timestamp
    IF OLD.status <> 1 AND NEW.status = 1 THEN
        UPDATE Menu_Orders_Items SET dispatched_at = NOW()
        WHERE menu_order_id = NEW.menu_order_id AND item_id = NEW.item_id
          AND dispatched_at IS NULL;

        SELECT user_id INTO v_user_id FROM Menu_Orders WHERE menu_order_id = NEW.menu_order_id;
        INSERT INTO Alerts (message)
        VALUES (CONCAT('Your order #', NEW.menu_order_id, ' is on the way!'));
        SET v_alert_id = LAST_INSERT_ID();
        INSERT INTO Alerted (alert_id, user_id, created_at) VALUES (v_alert_id, v_user_id, NOW());
    END IF;

    -- Delivered: log to Sales_History + timestamp
    IF OLD.status <> 2 AND NEW.status = 2 THEN
        UPDATE Menu_Orders_Items SET delivered_at = NOW()
        WHERE menu_order_id = NEW.menu_order_id AND item_id = NEW.item_id
          AND delivered_at IS NULL;

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


DELIMITER ;
