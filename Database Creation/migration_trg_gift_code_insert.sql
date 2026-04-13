USE SmartPlate;
DROP TRIGGER IF EXISTS trg_after_gift_code_insert;
DELIMITER $$

CREATE TRIGGER trg_after_gift_code_insert
AFTER INSERT ON Gift_Code
FOR EACH ROW
BEGIN
    DECLARE v_alert_id INT;
    DECLARE v_msg      VARCHAR(150);

    -- Gift_Code.type: 0 = percent-based, 1 = flat amount
    IF NEW.type = 0 THEN
        SET v_msg = CONCAT('New gift code ', NEW.code, ': ',
                           NEW.amount, '% off - valid until ', DATE(NEW.valid_to));
    ELSE
        SET v_msg = CONCAT('New gift code ', NEW.code, ': ',
                           NEW.amount, ' off - valid until ', DATE(NEW.valid_to));
    END IF;

    INSERT INTO Alerts (message) VALUES (v_msg);
    SET v_alert_id = LAST_INSERT_ID();

    INSERT INTO Alerted (alert_id, user_id, created_at)
    SELECT v_alert_id, c.user_id, NOW() FROM Customers c;
END$$

DELIMITER ;
