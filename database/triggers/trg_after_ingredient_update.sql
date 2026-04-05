-- -------------------------------------------------
-- TRIGGER 2: After Inventory_Batches quantity hits 0
-- Fires after UPDATE on Inventory_Batches
-- If quantity drops to 0, delete the batch
-- -------------------------------------------------

USE SmartPlate;

DELIMITER $$

CREATE TRIGGER trg_after_batch_update
AFTER UPDATE ON Inventory_Batches
FOR EACH ROW
BEGIN
    IF NEW.quantity <= 0 THEN
        DELETE FROM Inventory_Batches
        WHERE inventory_batch_id = NEW.inventory_batch_id;
    END IF;
END$$

DELIMITER ;