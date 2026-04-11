-- =================================================
-- SmartPlate Forecasting Layer (heuristic, SQL-only)
-- Phase 9b: daily-grain views + stored procedures that
-- compute predicted ingredient usage and dynamic prices
-- from Sales_History, Menu_Orders, Occasions, Weather_Data.
--
-- Runtime model: a manager/cron runs sp_RecomputeMinStocks
-- and sp_RecomputePricing for a target date; the results
-- land in Ingredient_Reorder_Forecast and
-- Item_Price_Override with applied=0. A second step
-- (sp_ApplyForecasts, sp_ApplyPricing) pushes them into
-- Ingredients.min_stock / Items.price and marks applied=1.
-- =================================================

USE SmartPlate;

-- ── Feature views ────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS v_daily_item_sales;
CREATE VIEW v_daily_item_sales AS
SELECT
    DATE(mo.order_time)          AS sale_date,
    oi.item_id,
    SUM(oi.quantity)             AS qty,
    COUNT(DISTINCT mo.menu_order_id) AS order_count
FROM Menu_Orders_Items oi
JOIN Menu_Orders mo ON oi.menu_order_id = mo.menu_order_id
GROUP BY DATE(mo.order_time), oi.item_id;

DROP VIEW IF EXISTS v_daily_ingredient_usage;
CREATE VIEW v_daily_ingredient_usage AS
SELECT
    s.sale_date,
    r.ingredient_id,
    SUM(s.qty * r.quantity) AS units_used
FROM v_daily_item_sales s
JOIN Recipes r ON r.item_id = s.item_id
GROUP BY s.sale_date, r.ingredient_id;

-- Per-date feature row: weather + occasion flag. LEFT JOINed so days
-- without weather/occasions still appear.
DROP VIEW IF EXISTS v_daily_features;
CREATE VIEW v_daily_features AS
SELECT
    d.sale_date,
    w.temperature,
    w.humidity,
    CASE WHEN o.occasion_id IS NOT NULL THEN 1 ELSE 0 END AS is_occasion,
    o.name AS occasion_name
FROM (SELECT DISTINCT sale_date FROM v_daily_item_sales) d
LEFT JOIN Weather_Data w ON w.date = d.sale_date
LEFT JOIN Occasions    o ON o.date = d.sale_date;

-- ── Forecasting procedures ──────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS sp_ForecastItemDemand;
DROP PROCEDURE IF EXISTS sp_RecomputeMinStocks;
DROP PROCEDURE IF EXISTS sp_RecomputePricing;
DROP PROCEDURE IF EXISTS sp_ApplyForecasts;
DROP PROCEDURE IF EXISTS sp_ApplyPricing;

DELIMITER $

-- Predict per-item demand for p_target_date.
-- Heuristic: average quantity on the same weekday over the
-- past 90 days, multiplied by an occasion boost (1.3 if
-- target_date is in Occasions) and a mild weather factor
-- (temperatures > 30°C reduce delivery by ~10%; rainy/humid
-- days > 80% humidity raise delivery by ~15%).
CREATE PROCEDURE sp_ForecastItemDemand(
    IN  p_item_id     INT,
    IN  p_target_date DATE,
    OUT p_predicted   DECIMAL(10,2)
)
BEGIN
    DECLARE v_base      DECIMAL(10,2) DEFAULT 0;
    DECLARE v_boost     DECIMAL(5,2)  DEFAULT 1.0;
    DECLARE v_weather   DECIMAL(5,2)  DEFAULT 1.0;
    DECLARE v_temp      DECIMAL(4,2);
    DECLARE v_hum       DECIMAL(5,2);

    SELECT COALESCE(AVG(qty), 0)
      INTO v_base
      FROM v_daily_item_sales
     WHERE item_id = p_item_id
       AND DAYOFWEEK(sale_date) = DAYOFWEEK(p_target_date)
       AND sale_date >= DATE_SUB(p_target_date, INTERVAL 90 DAY)
       AND sale_date <  p_target_date;

    IF EXISTS (SELECT 1 FROM Occasions WHERE `date` = p_target_date) THEN
        SET v_boost = 1.30;
    END IF;

    SELECT temperature, humidity INTO v_temp, v_hum
      FROM Weather_Data WHERE `date` = p_target_date;

    IF v_temp IS NOT NULL AND v_temp > 30 THEN
        SET v_weather = v_weather * 0.90;
    END IF;
    IF v_hum IS NOT NULL AND v_hum > 80 THEN
        SET v_weather = v_weather * 1.15;
    END IF;

    SET p_predicted = ROUND(v_base * v_boost * v_weather, 2);
END$

-- Writes per-ingredient predicted_min_stock into
-- Ingredient_Reorder_Forecast for p_target_date.
-- predicted_min_stock = SUM(item_demand * recipe.quantity) * safety factor.
CREATE PROCEDURE sp_RecomputeMinStocks(
    IN p_target_date DATE,
    IN p_safety      DECIMAL(4,2)  -- e.g. 1.50
)
BEGIN
    DECLARE v_boost   DECIMAL(5,2) DEFAULT 1.0;
    DECLARE v_weather DECIMAL(5,2) DEFAULT 1.0;
    DECLARE v_temp    DECIMAL(4,2);
    DECLARE v_hum     DECIMAL(5,2);

    IF p_safety IS NULL OR p_safety <= 0 THEN
        SET p_safety = 1.50;
    END IF;

    IF EXISTS (SELECT 1 FROM Occasions WHERE `date` = p_target_date) THEN
        SET v_boost = 1.30;
    END IF;
    SELECT temperature, humidity INTO v_temp, v_hum
      FROM Weather_Data WHERE `date` = p_target_date;
    IF v_temp IS NOT NULL AND v_temp > 30 THEN
        SET v_weather = v_weather * 0.90;
    END IF;
    IF v_hum IS NOT NULL AND v_hum > 80 THEN
        SET v_weather = v_weather * 1.15;
    END IF;

    INSERT INTO Ingredient_Reorder_Forecast
        (ingredient_id, forecast_date, predicted_min_stock, applied, generated_at)
    SELECT
        r.ingredient_id,
        p_target_date,
        ROUND(
            GREATEST(
                0,
                COALESCE(SUM(b.avg_qty * r.quantity), 0)
                * v_boost * v_weather * p_safety
            ),
            2
        ) AS predicted_min_stock,
        0, NOW()
    FROM Recipes r
    LEFT JOIN (
        SELECT
            oi.item_id,
            AVG(oi.quantity) AS avg_qty
        FROM Menu_Orders_Items oi
        JOIN Menu_Orders mo ON oi.menu_order_id = mo.menu_order_id
        WHERE mo.order_time >= DATE_SUB(p_target_date, INTERVAL 90 DAY)
          AND mo.order_time <  p_target_date
          AND DAYOFWEEK(DATE(mo.order_time)) = DAYOFWEEK(p_target_date)
        GROUP BY oi.item_id
    ) b ON b.item_id = r.item_id
    GROUP BY r.ingredient_id
    ON DUPLICATE KEY UPDATE
        predicted_min_stock = VALUES(predicted_min_stock),
        applied             = 0,
        generated_at        = NOW();
END$

-- Writes per-item dynamic price suggestions into Item_Price_Override.
-- For each item: compare forecast-day predicted demand to the item's
-- 90-day same-weekday median. 25% above median -> +10% premium.
-- 25% below median -> -10% discount. Otherwise keep current price.
CREATE PROCEDURE sp_RecomputePricing(
    IN p_target_date DATE
)
BEGIN
    INSERT INTO Item_Price_Override
        (item_id, effective_date, price, reason, applied, generated_at)
    SELECT
        i.item_id,
        p_target_date,
        CASE
            WHEN s.forecast_qty > s.median_qty * 1.25
                 THEN ROUND(i.price * 1.10, 2)
            WHEN s.forecast_qty < s.median_qty * 0.75
                 THEN ROUND(i.price * 0.90, 2)
            ELSE i.price
        END AS price,
        CASE
            WHEN s.forecast_qty > s.median_qty * 1.25 THEN 'high_demand_forecast'
            WHEN s.forecast_qty < s.median_qty * 0.75 THEN 'low_demand_discount'
            ELSE 'no_change'
        END AS reason,
        0, NOW()
    FROM Items i
    JOIN (
        SELECT
            r.item_id,
            -- 90-day same-weekday average as the forecast
            AVG(CASE
                WHEN DAYOFWEEK(DATE(mo.order_time)) = DAYOFWEEK(p_target_date)
                THEN oi.quantity END) AS forecast_qty,
            -- 90-day overall average as "normal"
            AVG(oi.quantity) AS median_qty
        FROM Items r
        LEFT JOIN Menu_Orders_Items oi ON oi.item_id = r.item_id
        LEFT JOIN Menu_Orders mo ON mo.menu_order_id = oi.menu_order_id
            AND mo.order_time >= DATE_SUB(p_target_date, INTERVAL 90 DAY)
            AND mo.order_time <  p_target_date
        WHERE r.is_active = 1
        GROUP BY r.item_id
    ) s ON s.item_id = i.item_id
    WHERE i.is_active = 1
    ON DUPLICATE KEY UPDATE
        price        = VALUES(price),
        reason       = VALUES(reason),
        applied      = 0,
        generated_at = NOW();
END$

-- Pushes applied=0 rows into Ingredients.min_stock for p_target_date
-- (or for a date range). Marks applied=1.
CREATE PROCEDURE sp_ApplyForecasts(
    IN p_target_date DATE
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE Ingredients ing
    JOIN Ingredient_Reorder_Forecast f
      ON f.ingredient_id = ing.ingredient_id
     AND f.forecast_date = p_target_date
     AND f.applied = 0
    SET ing.min_stock = f.predicted_min_stock;

    UPDATE Ingredient_Reorder_Forecast
    SET applied = 1
    WHERE forecast_date = p_target_date AND applied = 0;

    COMMIT;
END$

-- Pushes applied=0 price overrides into Items.price for p_target_date.
-- Skips reason='no_change' rows to avoid gratuitous writes.
CREATE PROCEDURE sp_ApplyPricing(
    IN p_target_date DATE
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE Items i
    JOIN Item_Price_Override o
      ON o.item_id = i.item_id
     AND o.effective_date = p_target_date
     AND o.applied = 0
     AND o.reason <> 'no_change'
    SET i.price = o.price;

    UPDATE Item_Price_Override
    SET applied = 1
    WHERE effective_date = p_target_date AND applied = 0;

    COMMIT;
END$

DELIMITER ;
