-- -------------------------------------------------
-- TRIGGER 3: After quantity reduces in Ingredients
-- Fires after UPDATE on Ingredients
-- If quantity <= min_stock, reorder from fastest supplier
-- -------------------------------------------------

USE SmartPlate;

DELIMITER $$

CREATE TRIGGER trg_after_ingredient_update
AFTER UPDATE ON Ingredients
FOR EACH ROW
BEGIN
    DECLARE reorder_supplier_id INT;

    IF NEW.quantity <= NEW.min_stock THEN
        -- Find the supplier with the lowest delivery_time for this ingredient
        SELECT s.supplier_id
        INTO reorder_supplier_id
        FROM Suppliers s
        INNER JOIN Supplies sp ON s.supplier_id = sp.supplier_id
        WHERE sp.ingredient_id = NEW.ingredient_id
            AND s.is_active = 1
        ORDER BY s.delivery_time ASC
        LIMIT 1;

        IF reorder_supplier_id IS NOT NULL THEN
            INSERT INTO Inventory_Batches (
                purchase_date,
                expiry_date,
                quantity,
                unit,
                cost,
                status,
                supplier_id,
                ingredient_id
            )
            VALUES (
                NOW(),
                DATE_ADD(NOW(), INTERVAL 6 WEEK),
                NEW.min_stock,
                NEW.unit,
                0,
                0,
                reorder_supplier_id,
                NEW.ingredient_id
            );
        END IF;
    END IF;
END$$

DELIMITER ;