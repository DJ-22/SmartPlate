USE SmartPlate;
DROP TRIGGER IF EXISTS trg_after_ingredient_insert;
DROP TRIGGER IF EXISTS trg_after_supplies_insert;
DELIMITER $$

-- New ingredient with no supplier: alert managers.
-- Otherwise fall through to the existing auto-order path.
CREATE TRIGGER trg_after_ingredient_insert
AFTER INSERT ON Ingredients
FOR EACH ROW
BEGIN
    DECLARE v_supplier_id INT DEFAULT NULL;
    DECLARE v_alert_id    INT;

    SELECT s.supplier_id INTO v_supplier_id
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
        INSERT INTO Inventory_Batches
            (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
        VALUES (NOW(), NULL, GREATEST(NEW.min_stock * 2, 1), NEW.unit, NULL, 0, v_supplier_id, NEW.ingredient_id);
    END IF;
END$$


-- First supplier for an ingredient: alert managers.
-- Subsequent suppliers for the same ingredient are a no-op.
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

DELIMITER ;
