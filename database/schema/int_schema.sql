-- =================================================
-- Auto-generated SQL DDL from ER_Diagram.mwb
-- =================================================

CREATE DATABASE IF NOT EXISTS mydb
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE mydb;

SET FOREIGN_KEY_CHECKS = 0;

-- -------------------------------------------------
-- Table: Allergens
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Allergens (
    `allergen_id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `description` VARCHAR(100),
    PRIMARY KEY (`allergen_id`)
);

-- -------------------------------------------------
-- Table: Roles
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Roles (
    `role_id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `description` VARCHAR(100),
    PRIMARY KEY (`role_id`)
);

-- -------------------------------------------------
-- Table: Permissions
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Permissions (
    `permission_id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `description` VARCHAR(100),
    PRIMARY KEY (`permission_id`)
);

-- -------------------------------------------------
-- Table: Category
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Category (
    `category_id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    PRIMARY KEY (`category_id`)
);

-- -------------------------------------------------
-- Table: Occasions
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Occasions (
    `occasion_id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `description` VARCHAR(100),
    PRIMARY KEY (`occasion_id`)
);

-- -------------------------------------------------
-- Table: Suppliers
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Suppliers (
    `supplier_id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `contact` VARCHAR(100) NOT NULL,
    `delivery_time` INT NOT NULL,
    `is_active` TINYINT NOT NULL,
    PRIMARY KEY (`supplier_id`),
    CONSTRAINT `chk_Suppliers_is_active` CHECK (`is_active` IN (0, 1))
);

-- -------------------------------------------------
-- Table: Ingredients
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Ingredients (
    `ingredient_id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `min_stock` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `unit` VARCHAR(15) NOT NULL,
    `quantity` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `allergen_id` INT NOT NULL,
    PRIMARY KEY (`ingredient_id`),
    CONSTRAINT `fk_Ingredients_Allergens`
        FOREIGN KEY (`allergen_id`)
        REFERENCES Allergens (`allergen_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Supplies
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Supplies (
    `supplier_id` INT NOT NULL,
    `ingredient_id` INT NOT NULL,
    PRIMARY KEY (`supplier_id`, `ingredient_id`),
    CONSTRAINT `fk_Suppliers_has_Ingredients_Suppliers1`
        FOREIGN KEY (`supplier_id`)
        REFERENCES Suppliers(`supplier_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Suppliers_has_Ingredients_Ingredients1`
        FOREIGN KEY (`ingredient_id`)
        REFERENCES Ingredients(`ingredient_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Inventory_Batches
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Inventory_Batches (
    `inventory_batch_id` INT NOT NULL AUTO_INCREMENT,
    `purchase_date` DATETIME NOT NULL,
    `expiry_date` DATETIME NOT NULL,
    `quantity` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `unit` VARCHAR(15) NOT NULL,
    `cost` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `status` TINYINT NOT NULL,
    `supplier_id` INT NOT NULL,
    `ingredient_id` INT NOT NULL,
    PRIMARY KEY (`inventory_batch_id`),
    CONSTRAINT `chk_Inventory_Batches_status` CHECK (`status` IN (0, 1, 2)),
    CONSTRAINT `fk_Inventory_Orders_Suppliers1`
        FOREIGN KEY (`supplier_id`)
        REFERENCES Suppliers(`supplier_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_Inventory_Orders_Ingredients1`
        FOREIGN KEY (`ingredient_id`)
        REFERENCES Ingredients(`ingredient_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Waste_Records
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Waste_Records (
    `waste_record_id` INT NOT NULL AUTO_INCREMENT,
    `quantity` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `timestamp` DATETIME NOT NULL,
    `inventory_batch_id` INT NOT NULL,
    PRIMARY KEY (`waste_record_id`),
    CONSTRAINT `fk_Waste_Records_Inventory_Batches1`
        FOREIGN KEY (`inventory_batch_id`)
        REFERENCES Inventory_Batches(`inventory_batch_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Logs
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Logs (
    `log_id` INT NOT NULL AUTO_INCREMENT,
    `timestamp` DATETIME NOT NULL,
    `quantity` DECIMAL(6,2) NOT NULL,
    `action` TINYINT NOT NULL,
    `ingredient_id` INT NOT NULL,
    PRIMARY KEY (`log_id`),
    CONSTRAINT `chk_Logs_action` CHECK (`action` IN (0, 1, 2)),
    CONSTRAINT `fk_Logs_Ingredients1`
        FOREIGN KEY (`ingredient_id`)
        REFERENCES Ingredients(`ingredient_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Items
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Items (
    `item_id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `description` VARCHAR(100),
    `price` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `prep_time` INT NOT NULL DEFAULT 0,
    `is_available` TINYINT NOT NULL,
    `category_id` INT NOT NULL,
    PRIMARY KEY (`item_id`),
    CONSTRAINT `chk_Items_is_available` CHECK (`is_available` IN (0, 1)),
    CONSTRAINT `fk_Items_Category1`
        FOREIGN KEY (`category_id`)
        REFERENCES Category(`category_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Nutritional_Info
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Nutritional_Info (
    `calories` INT DEFAULT 0,
    `protein` INT DEFAULT 0,
    `carbs` INT DEFAULT 0,
    `fat` INT DEFAULT 0,
    `fiber` INT DEFAULT 0,
    `item_id` INT NOT NULL,
    PRIMARY KEY (`item_id`),
    CONSTRAINT `fk_Nutritional_Info_Items1`
        FOREIGN KEY (`item_id`)
        REFERENCES Items(`item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Recipes
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Recipes (
    `item_id` INT NOT NULL,
    `ingredient_id` INT NOT NULL,
    `quantity` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `unit` VARCHAR(15) NOT NULL,
    PRIMARY KEY (`item_id`, `ingredient_id`),
    CONSTRAINT `fk_Items_has_Ingredients_Items1`
        FOREIGN KEY (`item_id`)
        REFERENCES Items(`item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Items_has_Ingredients_Ingredients1`
        FOREIGN KEY (`ingredient_id`)
        REFERENCES Ingredients(`ingredient_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Gift_Code
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Gift_Code (
    `gift_code_id` INT NOT NULL AUTO_INCREMENT,
    `code` VARCHAR(100) NOT NULL,
    `amount` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `type` TINYINT NOT NULL,
    `min_order` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `valid_from` DATETIME NOT NULL,
    `valid_to` DATETIME NOT NULL,
    PRIMARY KEY (`gift_code_id`),
    CONSTRAINT `chk_Gift_Code_type` CHECK (`type` IN (0, 1))
);

-- -------------------------------------------------
-- Table: Alerts
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Alerts (
    `alert_id` INT NOT NULL AUTO_INCREMENT,
    `message` VARCHAR(150),
    PRIMARY KEY (`alert_id`)
);

-- -------------------------------------------------
-- Table: Users
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Users (
    `user_id` INT NOT NULL AUTO_INCREMENT,
    `username` VARCHAR(100) NOT NULL,
    `email` VARCHAR(100) NOT NULL,
    `password_hash` VARCHAR(255) NOT NULL,
    `last_login` DATETIME NOT NULL,
    `role_id` INT NOT NULL,
    PRIMARY KEY (`user_id`),
    CONSTRAINT `fk_Users_Roles1`
        FOREIGN KEY (`role_id`)
        REFERENCES Roles(`role_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Employees
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Employees (
    `employee_id` INT NOT NULL AUTO_INCREMENT,
    `hire_date` DATETIME NOT NULL,
    `salary` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `user_id` INT NOT NULL,
    PRIMARY KEY (`employee_id`),
    CONSTRAINT `fk_Employees_Users1`
        FOREIGN KEY (`user_id`)
        REFERENCES Users(`user_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Customers
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Customers (
    `name` VARCHAR(100) NOT NULL,
    `visit_frequency` INT NOT NULL DEFAULT 0,
    `user_id` INT NOT NULL,
    PRIMARY KEY (`user_id`),
    CONSTRAINT `fk_Customers_Users1`
        FOREIGN KEY (`user_id`)
        REFERENCES Users(`user_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Menu_Orders
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Menu_Orders (
    `menu_order_id` INT NOT NULL AUTO_INCREMENT,
    `order_time` DATETIME NOT NULL,
    `price` DECIMAL(15,2) NOT NULL DEFAULT 0,
    `gift_code_id` INT,
    `user_id` INT NOT NULL,
    PRIMARY KEY (`menu_order_id`),
    CONSTRAINT `fk_Menu_Orders_Gift_Code1`
        FOREIGN KEY (`gift_code_id`)
        REFERENCES Gift_Code(`gift_code_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_Menu_Orders_Users1`
        FOREIGN KEY (`user_id`)
        REFERENCES Users(`user_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Menu_Orders_Items
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Menu_Orders_Items (
    `menu_order_id` INT NOT NULL,
    `item_id` INT NOT NULL,
    `quantity` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `status` TINYINT NOT NULL,
    PRIMARY KEY (`menu_order_id`, `item_id`),
    CONSTRAINT `chk_Menu_Orders_Items_status` CHECK (`status` IN (0, 1, 2)),
    CONSTRAINT `fk_Menu_Orders_has_Items_Menu_Orders1`
        FOREIGN KEY (`menu_order_id`)
        REFERENCES Menu_Orders(`menu_order_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Menu_Orders_has_Items_Items1`
        FOREIGN KEY (`item_id`)
        REFERENCES Items(`item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Permissions_Granted
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Permissions_Granted (
    `permission_id` INT NOT NULL,
    `role_id` INT NOT NULL,
    PRIMARY KEY (`permission_id`, `role_id`),
    CONSTRAINT `fk_Permissions_has_Roles_Permissions1`
        FOREIGN KEY (`permission_id`)
        REFERENCES Permissions(`permission_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Permissions_has_Roles_Roles1`
        FOREIGN KEY (`role_id`)
        REFERENCES Roles(`role_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Alerted
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Alerted (
    `alert_id` INT NOT NULL,
    `user_id` INT NOT NULL,
    `created_at` DATETIME NOT NULL,
    PRIMARY KEY (`alert_id`, `user_id`),
    CONSTRAINT `fk_Alerted_Alerts1`
        FOREIGN KEY (`alert_id`)
        REFERENCES Alerts(`alert_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_Alerted_Users1`
        FOREIGN KEY (`user_id`)
        REFERENCES Users(`user_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Sales_History
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Sales_History (
    `sales_history_id` INT NOT NULL AUTO_INCREMENT,
    `quantity` DECIMAL(6,2) NOT NULL DEFAULT 0,
    `item_id` INT NOT NULL,
    `occasion_id` INT NOT NULL,
    PRIMARY KEY (`sales_history_id`),
    CONSTRAINT `fk_Sales_History_Items1`
        FOREIGN KEY (`item_id`)
        REFERENCES Items(`item_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_Sales_History_Occasions1`
        FOREIGN KEY (`occasion_id`)
        REFERENCES Occasions(`occasion_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Sustainability_Records
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Sustainability_Records (
    `sustainability_record_id` INT NOT NULL AUTO_INCREMENT,
    `date` DATETIME NOT NULL,
    `carbon_footprint` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `menu_order_id` INT NOT NULL,
    PRIMARY KEY (`sustainability_record_id`),
    CONSTRAINT `fk_Sustainability_Records_Menu_Orders1`
        FOREIGN KEY (`menu_order_id`)
        REFERENCES Menu_Orders(`menu_order_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- -------------------------------------------------
-- Table: Compliance_Records
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Compliance_Records (
    `compliance_record_id` INT NOT NULL AUTO_INCREMENT,
    `inspection_date` DATETIME NOT NULL,
    `status` TINYINT NOT NULL,
    `description` VARCHAR(100),
    PRIMARY KEY (`compliance_record_id`),
    CONSTRAINT `chk_Compliance_Records_status` CHECK (`status` IN (0, 1, 2))
);

-- -------------------------------------------------
-- Table: Weather_Data
-- -------------------------------------------------
CREATE TABLE IF NOT EXISTS Weather_Data (
    `date` DATETIME NOT NULL,
    `temperature` DECIMAL(4,2) NOT NULL DEFAULT 0,
    `humidity` DECIMAL(5,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (`date`)
);

SET FOREIGN_KEY_CHECKS = 1;