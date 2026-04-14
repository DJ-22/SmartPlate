USE SmartPlate;

SET GLOBAL event_scheduler = ON;

DELIMITER $$

-- Runs daily: transitions batch statuses based on delivery_time elapsed
CREATE EVENT IF NOT EXISTS evt_update_batch_status
ON SCHEDULE EVERY 1 DAY
STARTS (DATE(NOW()) + INTERVAL 1 DAY)
DO
BEGIN
    -- Ordered -> Shipped (30% of delivery_time elapsed)
    UPDATE Inventory_Batches ib
    INNER JOIN Suppliers s ON ib.supplier_id = s.supplier_id
    SET ib.status = 1
    WHERE ib.status = 0
        AND TIMESTAMPDIFF(DAY, ib.purchase_date, NOW()) >= FLOOR(s.delivery_time * 0.30);

    -- Shipped -> Delivered (100% elapsed)
    UPDATE Inventory_Batches ib
    INNER JOIN Suppliers s ON ib.supplier_id = s.supplier_id
    SET ib.status = 2
    WHERE ib.status = 1
        AND TIMESTAMPDIFF(DAY, ib.purchase_date, NOW()) >= s.delivery_time;
END$$


-- Runs daily 1 minute after status update: expire batches past expiry_date
CREATE EVENT IF NOT EXISTS evt_expire_batches
ON SCHEDULE EVERY 1 DAY
STARTS (DATE(NOW()) + INTERVAL 1 DAY + INTERVAL 1 MINUTE)
DO
BEGIN
    INSERT INTO Waste_Records (quantity, timestamp, inventory_batch_id)
    SELECT quantity, NOW(), inventory_batch_id
    FROM Inventory_Batches
    WHERE status = 2 AND expiry_date IS NOT NULL AND expiry_date < NOW() AND quantity > 0;

    INSERT INTO Logs (timestamp, quantity, status, ingredient_id)
    SELECT NOW(), quantity, 2, ingredient_id
    FROM Inventory_Batches
    WHERE status = 2 AND expiry_date IS NOT NULL AND expiry_date < NOW() AND quantity > 0;

    UPDATE Ingredients i
    INNER JOIN (
        SELECT ingredient_id, SUM(quantity) AS total
        FROM Inventory_Batches
        WHERE status = 2 AND expiry_date IS NOT NULL AND expiry_date < NOW() AND quantity > 0
        GROUP BY ingredient_id
    ) exp ON i.ingredient_id = exp.ingredient_id
    SET i.quantity = GREATEST(0, i.quantity - exp.total);

    DELETE FROM Inventory_Batches
    WHERE status = 2 AND expiry_date IS NOT NULL AND expiry_date < NOW() AND quantity > 0;
END$$


DELIMITER ;
