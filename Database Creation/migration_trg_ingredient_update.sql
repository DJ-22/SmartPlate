USE SmartPlate;
DROP TRIGGER IF EXISTS trg_after_ingredient_update;
DELIMITER $$

-- Reorder whenever stock is at/below min_stock and no
-- batch is already in flight. The v_pending guard dedupes
-- so repeated updates at low stock don't stack orders.
CREATE TRIGGER trg_after_ingredient_update
AFTER UPDATE ON Ingredients
FOR EACH ROW
BEGIN
    DECLARE v_supplier_id INT;
    DECLARE v_pending     INT;

    IF NEW.quantity <= NEW.min_stock THEN
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
                INSERT INTO Inventory_Batches
                    (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id)
                VALUES (NOW(), NULL, GREATEST(NEW.min_stock * 2, 1), NEW.unit, NULL, 0, v_supplier_id, NEW.ingredient_id);
            END IF;
        END IF;
    END IF;
END$$

DELIMITER ;
