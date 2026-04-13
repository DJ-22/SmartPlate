USE SmartPlate;
DROP PROCEDURE IF EXISTS sp_AddOrderItem;
DELIMITER $$

CREATE PROCEDURE sp_AddOrderItem(
    IN p_order_id INT,
    IN p_item_id  INT,
    IN p_quantity DECIMAL(6,2)
)
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    IF p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be > 0';
    END IF;

    SELECT price INTO v_price FROM Items WHERE item_id = p_item_id AND is_active = 1;
    IF v_price IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item not found or not active';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Recipes WHERE item_id = p_item_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item has no recipe and cannot be ordered';
    END IF;

    START TRANSACTION;
    INSERT INTO Menu_Orders_Items (menu_order_id, item_id, quantity, status, prepared_at)
    VALUES (p_order_id, p_item_id, p_quantity, 0, NOW());
    UPDATE Menu_Orders SET price = price + (v_price * p_quantity)
    WHERE menu_order_id = p_order_id;
    COMMIT;
END$$

DELIMITER ;
