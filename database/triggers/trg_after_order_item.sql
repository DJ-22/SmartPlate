-- -------------------------------------------------
-- TRIGGER 1: After a dish is ordered
-- Fires after INSERT on Menu_Orders_Items
-- Reduces quantity in Ingredients and Inventory_Batches
-- Logs the usage with action = 1 (used)
-- -------------------------------------------------

USE SmartPlate;

DELIMITER $$

CREATE TRIGGER trg_after_order_item
AFTER INSERT ON Menu_Orders_Items
FOR EACH ROW
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE ing_id INT;
    DECLARE recipe_qty DECIMAL(6,2);
    DECLARE remaining DECIMAL(6,2);
    DECLARE batch_id INT;
    DECLARE batch_qty DECIMAL(6,2);
    DECLARE deduct DECIMAL(6,2);

    -- Cursor over all ingredients needed for the ordered item
    DECLARE ing_cursor CURSOR FOR
        SELECT ingredient_id, quantity
        FROM Recipes
        WHERE item_id = NEW.item_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN ing_cursor;

    ing_loop: LOOP
        FETCH ing_cursor INTO ing_id, recipe_qty;
        IF done THEN
            LEAVE ing_loop;
        END IF;

        -- Total quantity to deduct = recipe quantity * number of dishes ordered
        SET remaining = recipe_qty * NEW.quantity;

        -- Reduce from Ingredients table
        UPDATE Ingredients
        SET quantity = quantity - remaining
        WHERE ingredient_id = ing_id;

        -- Reduce from Inventory_Batches (FIFO by earliest expiry_date)
        batch_loop: WHILE remaining > 0 DO
            -- Get the batch with the earliest expiry date for this ingredient
            SELECT inventory_batch_id, quantity
            INTO batch_id, batch_qty
            FROM Inventory_Batches
            WHERE ingredient_id = ing_id
                AND status = 0
                AND quantity > 0
            ORDER BY expiry_date ASC
            LIMIT 1;

            IF batch_id IS NULL THEN
                LEAVE batch_loop;
            END IF;

            -- How much to deduct from this batch
            IF batch_qty >= remaining THEN
                SET deduct = remaining;
            ELSE
                SET deduct = batch_qty;
            END IF;

            -- Deduct from the batch
            UPDATE Inventory_Batches
            SET quantity = quantity - deduct
            WHERE inventory_batch_id = batch_id;

            -- Log the usage
            INSERT INTO Logs (timestamp, quantity, action, ingredient_id)
            VALUES (NOW(), deduct, 1, ing_id);

            SET remaining = remaining - deduct;
            SET batch_id = NULL;
        END WHILE batch_loop;

    END LOOP ing_loop;

    CLOSE ing_cursor;
END$$

DELIMITER ;