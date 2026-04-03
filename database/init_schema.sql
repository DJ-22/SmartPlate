CREATE DATABASE IF NOT EXISTS SmartPlate;
USE SmartPlate;

-- =========================================================================
-- USER MANAGEMENT
CREATE TABLE users_roles (
    role_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50),
    description TEXT
);

CREATE TABLE users_permissions(
    permission_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50),
    description TEXT
);

CREATE TABLE users_permissions_granted(
    permission_id INT,
    role_id INT,
    PRIMARY KEY(permission_id, role_id),
    FOREIGN KEY(permission_id) REFERENCES users_permissions(permission_id),
    FOREIGN KEY(role_id) REFERENCES users_roles(role_id)
);

CREATE TABLE users_users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50),
    email VARCHAR(100),
    password_hash VARCHAR(255),
    role_id INT,
    last_login DATETIME,
    FOREIGN KEY (role_id) REFERENCES users_roles(role_id)
);

CREATE TABLE users_employees (
    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    role_id INT,
    hire_date DATE,
    salary DECIMAL(10, 2),
    FOREIGN KEY (role_id) REFERENCES users_roles(role_id)
);
-- =========================================================================

-- MENU
CREATE TABLE menu_categories (
    category_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50)
);

CREATE TABLE menu_allergens (
    allergen_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50),
    description TEXT
);

CREATE TABLE menu_items (
    item_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100),
    description TEXT,
    price DECIMAL(10, 2),
    prep_time INT,
    category_id INT,
    is_available BOOLEAN,
    FOREIGN KEY (category_id) REFERENCES menu_categories(category_id)
);

CREATE TABLE menu_nutritional_info (
    item_id INT PRIMARY KEY,
    calories INT,
    protein DECIMAL(5, 2),
    carbs DECIMAL(5, 2),
    fat DECIMAL(5, 2),
    fiber DECIMAL(5, 2),
    sodium DECIMAL(5, 2),
    FOREIGN KEY (item_id) REFERENCES menu_items(item_id)
);
-- =========================================================================

-- INVENTORY
CREATE TABLE inventory_ingredients (
    ingredient_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100),
    allergen_id INT,
    min_stock INT,
    unit VARCHAR(20),
    quantity INT,
    FOREIGN KEY (allergen_id) REFERENCES menu_allergens(allergen_id)
);

CREATE TABLE inventory_suppliers (
    sup_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100),
    contact VARCHAR(100),
    delivery_time INT,
    is_active BOOLEAN
);

CREATE TABLE inventory_supplies (
    sup_id INT,
    ingredient_id INT,
    PRIMARY KEY (sup_id, ingredient_id),
    FOREIGN KEY (sup_id) REFERENCES inventory_suppliers(sup_id),
    FOREIGN KEY (ingredient_id) REFERENCES inventory_ingredients(ingredient_id)
);

CREATE TABLE inventory_orders (
    inventory_order_id INT PRIMARY KEY AUTO_INCREMENT,
    sup_id INT,
    ingredient_id INT,
    purchase_date DATE,
    expiry_date DATE,
    quantity INT,
    unit VARCHAR(20),
    cost DECIMAL(10, 2),
    status VARCHAR(50),
    FOREIGN KEY (sup_id) REFERENCES inventory_suppliers(sup_id),
    FOREIGN KEY (ingredient_id) REFERENCES inventory_ingredients(ingredient_id)
);

CREATE TABLE inventory_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    ingredient_id INT,
    timestamp DATETIME,
    quantity INT,
    action VARCHAR(50),
    FOREIGN KEY (ingredient_id) REFERENCES inventory_ingredients(ingredient_id)
);

-- Junction table for Recipes (Many-to-Many between Items and Ingredients)
CREATE TABLE menu_recipes (
    item_id INT,
    ingredient_id INT,
    quantity INT,
    unit VARCHAR(20),
    PRIMARY KEY (item_id, ingredient_id),
    FOREIGN KEY (item_id) REFERENCES menu_items(item_id),
    FOREIGN KEY (ingredient_id) REFERENCES inventory_ingredients(ingredient_id)
);
-- =========================================================================

-- SALES
CREATE TABLE sales_customers (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    name VARCHAR(100),
    contact VARCHAR(100),
    visit_frequency INT,
    FOREIGN KEY (user_id) REFERENCES users_users(user_id)
);

CREATE TABLE sales_gift_codes (
    gift_code_id INT PRIMARY KEY AUTO_INCREMENT,
    code VARCHAR(50),
    amount DECIMAL(10, 2),
    type VARCHAR(20),
    min_order DECIMAL(10, 2),
    valid_from DATE,
    valid_to DATE
);

CREATE TABLE sales_menu_orders (
    menu_order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT,
    order_time DATETIME,
    price DECIMAL(10, 2),
    discount DECIMAL(10, 2),
    FOREIGN KEY (customer_id) REFERENCES sales_customers(customer_id)
);

CREATE TABLE sales_menu_orders_items (
    menu_order_id INT,
    item_id INT,
    quantity INT,
    status VARCHAR(50),
    PRIMARY KEY (menu_order_id, item_id),
    FOREIGN KEY (menu_order_id) REFERENCES sales_menu_orders(menu_order_id),
    FOREIGN KEY (item_id) REFERENCES menu_items(item_id)
);
-- =========================================================================

-- WASTE TRACKING
CREATE TABLE waste_categories (
    waste_id INT PRIMARY KEY AUTO_INCREMENT,
    category VARCHAR(50),
    description TEXT
);

CREATE TABLE waste_records (
    waste_record_id INT PRIMARY KEY AUTO_INCREMENT,
    waste_id INT,
    ingredient_id INT,
    item_id INT,
    quantity INT,
    menu_order_id INT,
    timestamp DATETIME,
    FOREIGN KEY (waste_id) REFERENCES waste_categories(waste_id),
    FOREIGN KEY (ingredient_id) REFERENCES inventory_ingredients(ingredient_id),
    FOREIGN KEY (item_id) REFERENCES menu_items(item_id),
    FOREIGN KEY (menu_order_id) REFERENCES sales_menu_orders(menu_order_id)
);
-- =========================================================================

-- DEMAND FORECASTING
CREATE TABLE forecast_occasions (
    occasion_id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100),
    description TEXT
);

CREATE TABLE forecast_weather_data (
    date DATE PRIMARY KEY,
    temp DECIMAL(5, 2),
    humidity DECIMAL(5, 2)
);

CREATE TABLE forecast_sales_history (
    history_id INT PRIMARY KEY AUTO_INCREMENT,
    item_id INT,
    quantity INT,
    occasion_id INT,
    FOREIGN KEY (item_id) REFERENCES menu_items(item_id),
    FOREIGN KEY (occasion_id) REFERENCES forecast_occasions(occasion_id)
);
-- =========================================================================

-- SUSTAINABILITY
CREATE TABLE sustainability_records (
    sustainability_record_id INT PRIMARY KEY AUTO_INCREMENT,
    date DATE,
    menu_order_id INT,
    carbon_footprint DECIMAL(10, 2),
    FOREIGN KEY (menu_order_id) REFERENCES sales_menu_orders(menu_order_id)
);

CREATE TABLE sustainability_compliance_records (
    compliance_record_id INT PRIMARY KEY AUTO_INCREMENT,
    inspection_date DATE,
    status VARCHAR(50),
    description TEXT
);
-- =========================================================================

-- NOTIFICATION ALERTS
CREATE TABLE alerts_types (
    alert_id INT PRIMARY KEY AUTO_INCREMENT,
    message TEXT
);

CREATE TABLE alerts_alerted (
    alert_id INT,
    user_id INT,
    created_at DATETIME,
    PRIMARY KEY (alert_id, user_id),
    FOREIGN KEY (alert_id) REFERENCES alerts_types(alert_id),
    FOREIGN KEY (user_id) REFERENCES users_users(user_id)
);
-- =========================================================================