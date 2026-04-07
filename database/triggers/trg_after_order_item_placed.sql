-- -------------------------------------------------
-- TRIGGER 4: New Order Item -> Alert All Chef/Kitchen Staff
-- Fires AFTER INSERT on Menu_Orders_Items
-- Creates an alert and notifies every active employee
-- whose role is 'chef' or 'kitchen'.
-- -------------------------------------------------

USE SmartPlate;

DELIMITER $$

CREATE TRIGGER trg_after_order_item_placed
AFTER INSERT ON Menu_Orders_Items
FOR EACH ROW
BEGIN
    DECLARE v_alert_id   INT;
    DECLARE v_user_id    INT;
    DECLARE done         INT DEFAULT 0;

    -- Cursor: fetch all kitchen/chef employee user_ids
    DECLARE chef_cursor CURSOR FOR
        SELECT u.user_id
        FROM Users u
        INNER JOIN Roles r ON u.role_id = r.role_id
        INNER JOIN Employees e ON e.user_id = u.user_id
        WHERE LOWER(r.name) IN ('chef', 'kitchen');

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- 1. Create one alert for this order item
    INSERT INTO Alerts (message)
    VALUES (CONCAT('New dish to prepare: Order #', NEW.menu_order_id,
                   ', Item #', NEW.item_id,
                   ' x', NEW.quantity));

    SET v_alert_id = LAST_INSERT_ID();

    -- 2. Notify every chef / kitchen staff member
    OPEN chef_cursor;

    chef_loop: LOOP
        FETCH chef_cursor INTO v_user_id;
        IF done THEN
            LEAVE chef_loop;
        END IF;

        INSERT INTO Alerted (alert_id, user_id, created_at)
        VALUES (v_alert_id, v_user_id, NOW());
    END LOOP chef_loop;

    CLOSE chef_cursor;
END$$

DELIMITER ;