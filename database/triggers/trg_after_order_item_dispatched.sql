-- =================================================
-- TRIGGER 5: Order Item Status -> 1 (Out for Delivery) -> Alert the Customer
-- Fires AFTER UPDATE on Menu_Orders_Items
-- Watches for status changing from 0 (pending) to 1 (out for delivery)
-- Looks up the customer via Menu_Orders and notifies them.
-- =================================================

USE SmartPlate;

DELIMITER $$

CREATE TRIGGER trg_after_order_item_dispatched
AFTER UPDATE ON Menu_Orders_Items
FOR EACH ROW
BEGIN
    DECLARE v_alert_id   INT;
    DECLARE v_user_id    INT;

    -- Only fire when status flips to 1 (out for delivery)
    IF OLD.status <> 1 AND NEW.status = 1 THEN

        -- 1. Get the customer's user_id from the parent order
        SELECT user_id
        INTO   v_user_id
        FROM   Menu_Orders
        WHERE  menu_order_id = NEW.menu_order_id;

        -- 2. Create the delivery alert
        INSERT INTO Alerts (message)
        VALUES (CONCAT('Your order #', NEW.menu_order_id,
                       ' is on the way!'));

        SET v_alert_id = LAST_INSERT_ID();

        -- 3. Link the alert to the customer
        INSERT INTO Alerted (alert_id, user_id, created_at)
        VALUES (v_alert_id, v_user_id, NOW());

    END IF;
END$$

DELIMITER ;
