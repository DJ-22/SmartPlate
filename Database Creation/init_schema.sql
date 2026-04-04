-- =================================================
-- SmartPlate Database Schema
-- =================================================

CREATE DATABASE IF NOT EXISTS SmartPlate
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE SmartPlate;

SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS Allergens (
    `allergen_id` INT NOT NULL AUTO_INCREMENT,
    `name`        VARCHAR(100) NOT NULL,
    `description` VARCHAR(100),
    PRIMARY KEY (`allergen_id`)
);

CREATE TABLE IF NOT EXISTS Roles (
    `role_id`     INT NOT NULL AUTO_INCREMENT,
    `name`        VARCHAR(100) NOT NULL,
    `description` VARCHAR(100),
    PRIMARY KEY (`role_id`)
);

CREATE TABLE IF NOT EXISTS Permissions (
    `permission_id` INT NOT NULL AUTO_INCREMENT,
    `name`          VARCHAR(100) NOT NULL,
    `description`   VARCHAR(100),
    PRIMARY KEY (`permission_id`)
);

CREATE TABLE IF NOT EXISTS Category (
    `category_id` INT NOT NULL AUTO_INCREMENT,
    `name`        VARCHAR(100) NOT NULL,
    PRIMARY KEY (`category_id`)
);

CREATE TABLE IF NOT EXISTS Occasions (
    `occasion_id` INT NOT NULL AUTO_INCREMENT,
    `name`        VARCHAR(100) NOT NULL,
    `description` VARCHAR(100),
    -- D10: daily-grain date for ML features
    `date`        DATE,
    PRIMARY KEY (`occasion_id`),
    -- D18: unique name so trigger fallback ('Regular') dedupes cleanly
    UNIQUE KEY `uk_Occasions_name` (`name`)
);

CREATE TABLE IF NOT EXISTS Users (
    `user_id`       INT NOT NULL AUTO_INCREMENT,
    `username`      VARCHAR(100) NOT NULL,
    `email`         VARCHAR(100) NOT NULL,
    `password_hash` VARCHAR(255) NOT NULL,
    `last_login`    DATETIME NOT NULL,
    `role_id`       INT NOT NULL,
    PRIMARY KEY (`user_id`),
    -- D5: prevent duplicate usernames / emails
    UNIQUE KEY `uk_Users_username` (`username`),
    UNIQUE KEY `uk_Users_email`    (`email`),
    CONSTRAINT `fk_Users_Roles`
        FOREIGN KEY (`role_id`) REFERENCES Roles(`role_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Suppliers (
    `supplier_id`   INT NOT NULL AUTO_INCREMENT,
    `name`          VARCHAR(100) NOT NULL,
    `contact`       VARCHAR(100) NOT NULL,
    `delivery_time` INT NOT NULL DEFAULT 1,
    `is_active`     TINYINT NOT NULL DEFAULT 1,
    `user_id`       INT,
    PRIMARY KEY (`supplier_id`),
    CONSTRAINT `chk_Suppliers_is_active` CHECK (`is_active` IN (0, 1)),
    CONSTRAINT `fk_Suppliers_Users`
        FOREIGN KEY (`user_id`) REFERENCES Users(`user_id`)
        ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Ingredients (
    `ingredient_id` INT NOT NULL AUTO_INCREMENT,
    `name`          VARCHAR(100) NOT NULL,
    `min_stock`     DECIMAL(6,2) NOT NULL DEFAULT 0,
    `unit`          VARCHAR(15) NOT NULL,
    `quantity`      DECIMAL(6,2) NOT NULL DEFAULT 0,
    `allergen_id`   INT NOT NULL,
    PRIMARY KEY (`ingredient_id`),
    -- D9: stock can never go negative
    CONSTRAINT `chk_Ingredients_quantity` CHECK (`quantity` >= 0),
    CONSTRAINT `chk_Ingredients_min_stock` CHECK (`min_stock` >= 0),
    CONSTRAINT `fk_Ingredients_Allergens`
        FOREIGN KEY (`allergen_id`) REFERENCES Allergens(`allergen_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Supplies (
    `supplier_id`    INT NOT NULL,
    `ingredient_id`  INT NOT NULL,
    `price_per_unit` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `unit`           VARCHAR(15) NOT NULL DEFAULT 'kg',
    PRIMARY KEY (`supplier_id`, `ingredient_id`),
    CONSTRAINT `fk_Supplies_Suppliers`
        FOREIGN KEY (`supplier_id`) REFERENCES Suppliers(`supplier_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Supplies_Ingredients`
        FOREIGN KEY (`ingredient_id`) REFERENCES Ingredients(`ingredient_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Inventory_Batches (
    `inventory_batch_id` INT NOT NULL AUTO_INCREMENT,
    `purchase_date`      DATETIME NOT NULL,
    `expiry_date`        DATETIME,
    `quantity`           DECIMAL(6,2) NOT NULL DEFAULT 0,
    `unit`               VARCHAR(15),
    `cost`               DECIMAL(10,2) DEFAULT 0,
    -- 0=ordered, 1=shipped (>=30% delivery time), 2=delivered (available)
    `status`             TINYINT NOT NULL DEFAULT 0,
    `supplier_id`        INT NOT NULL,
    `ingredient_id`      INT NOT NULL,
    PRIMARY KEY (`inventory_batch_id`),
    CONSTRAINT `chk_Inventory_Batches_status` CHECK (`status` IN (0, 1, 2)),
    CONSTRAINT `fk_Inventory_Batches_Suppliers`
        FOREIGN KEY (`supplier_id`) REFERENCES Suppliers(`supplier_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_Inventory_Batches_Ingredients`
        FOREIGN KEY (`ingredient_id`) REFERENCES Ingredients(`ingredient_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Waste_Records (
    `waste_record_id`    INT NOT NULL AUTO_INCREMENT,
    `quantity`           DECIMAL(6,2) NOT NULL DEFAULT 0,
    `timestamp`          DATETIME NOT NULL,
    `inventory_batch_id` INT NOT NULL,
    PRIMARY KEY (`waste_record_id`),
    -- D13: FK to the batch (was missing); D12: index implicit via FK
    KEY `ix_Waste_Records_batch` (`inventory_batch_id`),
    CONSTRAINT `fk_Waste_Records_Batch`
        FOREIGN KEY (`inventory_batch_id`) REFERENCES Inventory_Batches(`inventory_batch_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Logs (
    `log_id`        INT NOT NULL AUTO_INCREMENT,
    `timestamp`     DATETIME NOT NULL,
    `quantity`      DECIMAL(6,2) NOT NULL,
    -- 0=in_storage, 1=used, 2=expired
    `status`        TINYINT NOT NULL,
    `ingredient_id` INT NOT NULL,
    PRIMARY KEY (`log_id`),
    -- D12: explicit FK index for fast lookup by ingredient
    KEY `ix_Logs_ingredient` (`ingredient_id`),
    CONSTRAINT `chk_Logs_status` CHECK (`status` IN (0, 1, 2)),
    CONSTRAINT `fk_Logs_Ingredients`
        FOREIGN KEY (`ingredient_id`) REFERENCES Ingredients(`ingredient_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Items (
    `item_id`      INT NOT NULL AUTO_INCREMENT,
    `name`         VARCHAR(100) NOT NULL,
    `description`  VARCHAR(100),
    -- D7: wider price column
    `price`        DECIMAL(10,2) NOT NULL DEFAULT 0,
    `prep_time`    INT NOT NULL DEFAULT 0,
    `is_active`    TINYINT NOT NULL DEFAULT 1,
    `category_id`  INT NOT NULL,
    PRIMARY KEY (`item_id`),
    -- D12: index the category FK for menu-by-category lookups
    KEY `ix_Items_category` (`category_id`),
    CONSTRAINT `chk_Items_is_active` CHECK (`is_active` IN (0, 1)),
    CONSTRAINT `fk_Items_Category`
        FOREIGN KEY (`category_id`) REFERENCES Category(`category_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Nutritional_Info (
    -- D11: NULL distinguishes "unknown" from "zero"
    `calories` INT,
    `protein`  INT,
    `carbs`    INT,
    `fat`      INT,
    `fiber`    INT,
    `item_id`  INT NOT NULL,
    PRIMARY KEY (`item_id`),
    CONSTRAINT `fk_Nutritional_Info_Items`
        FOREIGN KEY (`item_id`) REFERENCES Items(`item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Recipes (
    `item_id`       INT NOT NULL,
    `ingredient_id` INT NOT NULL,
    `quantity`      DECIMAL(6,2) NOT NULL DEFAULT 0,
    `unit`          VARCHAR(15) NOT NULL,
    PRIMARY KEY (`item_id`, `ingredient_id`),
    CONSTRAINT `fk_Recipes_Items`
        FOREIGN KEY (`item_id`) REFERENCES Items(`item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Recipes_Ingredients`
        FOREIGN KEY (`ingredient_id`) REFERENCES Ingredients(`ingredient_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Gift_Code (
    `gift_code_id` INT NOT NULL AUTO_INCREMENT,
    `code`         VARCHAR(100) NOT NULL,
    -- D8: widened to support flat discounts > 9999.99
    `amount`       DECIMAL(10,2) NOT NULL DEFAULT 0,
    `type`         TINYINT NOT NULL DEFAULT 0,
    `min_order`    DECIMAL(10,2) NOT NULL DEFAULT 0,
    `valid_from`   DATETIME NOT NULL,
    `valid_to`     DATETIME NOT NULL,
    PRIMARY KEY (`gift_code_id`),
    UNIQUE KEY `uk_Gift_Code_code` (`code`),
    CONSTRAINT `chk_Gift_Code_type` CHECK (`type` IN (0, 1))
);

CREATE TABLE IF NOT EXISTS Alerts (
    `alert_id` INT NOT NULL AUTO_INCREMENT,
    `message`  VARCHAR(150),
    PRIMARY KEY (`alert_id`)
);

CREATE TABLE IF NOT EXISTS Employees (
    `employee_id` INT NOT NULL AUTO_INCREMENT,
    `hire_date`   DATETIME NOT NULL,
    `salary`      DECIMAL(15,2) NOT NULL DEFAULT 0,
    `user_id`     INT NOT NULL,
    PRIMARY KEY (`employee_id`),
    CONSTRAINT `fk_Employees_Users`
        FOREIGN KEY (`user_id`) REFERENCES Users(`user_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Customers (
    -- D6: surrogate PK so future joins don't leak user_id everywhere
    `customer_id`     INT NOT NULL AUTO_INCREMENT,
    `name`            VARCHAR(100) NOT NULL,
    `visit_frequency` INT NOT NULL DEFAULT 0,
    `user_id`         INT NOT NULL,
    PRIMARY KEY (`customer_id`),
    UNIQUE KEY `uk_Customers_user` (`user_id`),
    CONSTRAINT `fk_Customers_Users`
        FOREIGN KEY (`user_id`) REFERENCES Users(`user_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Menu_Orders (
    `menu_order_id` INT NOT NULL AUTO_INCREMENT,
    `order_time`    DATETIME NOT NULL,
    `price`         DECIMAL(15,2) NOT NULL DEFAULT 0,
    `gift_code_id`  INT,
    `user_id`       INT NOT NULL,
    PRIMARY KEY (`menu_order_id`),
    CONSTRAINT `fk_Menu_Orders_Gift_Code`
        FOREIGN KEY (`gift_code_id`) REFERENCES Gift_Code(`gift_code_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_Menu_Orders_Users`
        FOREIGN KEY (`user_id`) REFERENCES Users(`user_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Menu_Orders_Items (
    `menu_order_id` INT NOT NULL,
    `item_id`       INT NOT NULL,
    `quantity`      DECIMAL(6,2) NOT NULL DEFAULT 0,
    -- 0=being prepared, 1=out for delivery, 2=delivered; deleted on cancel
    `status`        TINYINT NOT NULL DEFAULT 0,
    -- D14: SLA timestamps for ML features
    `prepared_at`   DATETIME,
    `dispatched_at` DATETIME,
    `delivered_at`  DATETIME,
    PRIMARY KEY (`menu_order_id`, `item_id`),
    KEY `ix_Menu_Orders_Items_item` (`item_id`),
    CONSTRAINT `chk_Menu_Orders_Items_status` CHECK (`status` IN (0, 1, 2)),
    CONSTRAINT `fk_Menu_Orders_Items_Orders`
        FOREIGN KEY (`menu_order_id`) REFERENCES Menu_Orders(`menu_order_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Menu_Orders_Items_Items`
        FOREIGN KEY (`item_id`) REFERENCES Items(`item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Permissions_Granted (
    `permission_id` INT NOT NULL,
    `role_id`       INT NOT NULL,
    PRIMARY KEY (`permission_id`, `role_id`),
    CONSTRAINT `fk_Permissions_Granted_Permissions`
        FOREIGN KEY (`permission_id`) REFERENCES Permissions(`permission_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Permissions_Granted_Roles`
        FOREIGN KEY (`role_id`) REFERENCES Roles(`role_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Alerted (
    `alert_id`   INT NOT NULL,
    `user_id`    INT NOT NULL,
    `created_at` DATETIME NOT NULL,
    -- U7: track when the alert was read
    `read_at`    DATETIME,
    PRIMARY KEY (`alert_id`, `user_id`),
    -- D17: index for "my alerts" lookups
    KEY `ix_Alerted_user` (`user_id`),
    CONSTRAINT `fk_Alerted_Alerts`
        FOREIGN KEY (`alert_id`) REFERENCES Alerts(`alert_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Alerted_Users`
        FOREIGN KEY (`user_id`) REFERENCES Users(`user_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Sales_History (
    `sales_history_id` INT NOT NULL AUTO_INCREMENT,
    `quantity`         DECIMAL(6,2) NOT NULL DEFAULT 0,
    `item_id`          INT NOT NULL,
    `menu_order_id`    INT NOT NULL,
    `occasion_id`      INT NOT NULL,
    PRIMARY KEY (`sales_history_id`),
    -- D12: FK indexes for reporting queries
    KEY `ix_Sales_History_item`  (`item_id`),
    KEY `ix_Sales_History_order` (`menu_order_id`),
    KEY `ix_Sales_History_occ`   (`occasion_id`),
    CONSTRAINT `fk_Sales_History_Items`
        FOREIGN KEY (`item_id`) REFERENCES Items(`item_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_Sales_History_Menu_Orders`
        FOREIGN KEY (`menu_order_id`) REFERENCES Menu_Orders(`menu_order_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_Sales_History_Occasions`
        FOREIGN KEY (`occasion_id`) REFERENCES Occasions(`occasion_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Sustainability_Records (
    `sustainability_record_id` INT NOT NULL AUTO_INCREMENT,
    `date`                     DATETIME NOT NULL,
    `carbon_footprint`         DECIMAL(10,2) NOT NULL DEFAULT 0,
    -- D15: per-item attribution so ML can aggregate carbon/item
    `item_id`                  INT,
    `menu_order_id`            INT NOT NULL,
    PRIMARY KEY (`sustainability_record_id`),
    KEY `ix_Sustainability_order` (`menu_order_id`),
    KEY `ix_Sustainability_item`  (`item_id`),
    CONSTRAINT `fk_Sustainability_Records_Orders`
        FOREIGN KEY (`menu_order_id`) REFERENCES Menu_Orders(`menu_order_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_Sustainability_Records_Items`
        FOREIGN KEY (`item_id`) REFERENCES Items(`item_id`)
        ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS Compliance_Records (
    `compliance_record_id` INT NOT NULL AUTO_INCREMENT,
    `inspection_date`      DATETIME NOT NULL,
    -- 0=waiting, 1=passed, 2=failed
    `status`               TINYINT NOT NULL,
    `description`          VARCHAR(100),
    PRIMARY KEY (`compliance_record_id`),
    CONSTRAINT `chk_Compliance_Records_status` CHECK (`status` IN (0, 1, 2))
);

CREATE TABLE IF NOT EXISTS Weather_Data (
    -- D10: daily-grain key prevents per-hour duplicates
    `date`        DATE NOT NULL,
    `temperature` DECIMAL(4,2) NOT NULL DEFAULT 0,
    `humidity`    DECIMAL(5,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (`date`)
);

SET FOREIGN_KEY_CHECKS = 1;
