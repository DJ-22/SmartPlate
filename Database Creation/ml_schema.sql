-- =================================================
-- SmartPlate ML / Forecasting Schema
-- Phase 9a: write-back targets for the SQL heuristic
-- prediction layer. These are the only tables the
-- forecasting procedures MUTATE; everything else they
-- read from is existing history/feature data.
-- =================================================

USE SmartPlate;

-- Predicted reorder thresholds per ingredient per day.
-- Managers apply these into Ingredients.min_stock explicitly
-- so forecasts never silently clobber human-set values.
CREATE TABLE IF NOT EXISTS Ingredient_Reorder_Forecast (
    `forecast_id`         INT NOT NULL AUTO_INCREMENT,
    `ingredient_id`       INT NOT NULL,
    `forecast_date`       DATE NOT NULL,
    `predicted_min_stock` DECIMAL(10,2) NOT NULL,
    `applied`             TINYINT NOT NULL DEFAULT 0,
    `generated_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`forecast_id`),
    UNIQUE KEY `uk_IRF_ing_date` (`ingredient_id`, `forecast_date`),
    KEY `ix_IRF_date` (`forecast_date`),
    CONSTRAINT `chk_IRF_applied` CHECK (`applied` IN (0, 1)),
    CONSTRAINT `chk_IRF_predicted_nonneg` CHECK (`predicted_min_stock` >= 0),
    CONSTRAINT `fk_IRF_Ingredients`
        FOREIGN KEY (`ingredient_id`) REFERENCES Ingredients(`ingredient_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- Dynamic-pricing suggestions per item per effective date.
-- `reason` is a short free-text tag produced by the heuristic
-- (e.g. 'high_demand_forecast', 'low_demand_discount').
CREATE TABLE IF NOT EXISTS Item_Price_Override (
    `override_id`    INT NOT NULL AUTO_INCREMENT,
    `item_id`        INT NOT NULL,
    `effective_date` DATE NOT NULL,
    `price`          DECIMAL(10,2) NOT NULL,
    `reason`         VARCHAR(100),
    `applied`        TINYINT NOT NULL DEFAULT 0,
    `generated_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`override_id`),
    UNIQUE KEY `uk_IPO_item_date` (`item_id`, `effective_date`),
    KEY `ix_IPO_date` (`effective_date`),
    CONSTRAINT `chk_IPO_applied` CHECK (`applied` IN (0, 1)),
    CONSTRAINT `chk_IPO_price_nonneg` CHECK (`price` >= 0),
    CONSTRAINT `fk_IPO_Items`
        FOREIGN KEY (`item_id`) REFERENCES Items(`item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);
