USE SmartPlate;
DROP TRIGGER IF EXISTS trg_after_ingredient_update;
DROP TRIGGER IF EXISTS trg_after_ingredient_insert;
DELIMITER $$

-- Auto-reorder when stock <= min_stock. Cost = qty * price_per_unit
-- pulled from Supplies for the chosen (cheapest-delivery) supplier.
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


-- New ingredient: no-supplier alert OR auto-order (with computed cost).
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
        SET v_order_qty = GREATEST(NEW.min_stock * 2, 1);
        INSERT INTO Inventory_Batches
            (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
        VALUES (NOW(), NULL, v_order_qty, NEW.unit,
                v_order_qty * COALESCE(v_price_per_unit, 0),
                0, v_supplier_id, NEW.ingredient_id);
    END IF;
END$$

DELIMITER ;
