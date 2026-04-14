USE SmartPlate;

-- ── Allergens ────────────────────────────────────────────────────────────────
INSERT IGNORE INTO Allergens (name, description) VALUES
('None',    'No allergen'),
('Gluten',  'Wheat, barley, rye'),
('Dairy',   'Milk and milk products'),
('Eggs',    'Egg and egg products'),
('Nuts',    'Tree nuts and peanuts'),
('Soy',     'Soybean products'),
('Seafood', 'Fish and shellfish');

-- ── Roles ────────────────────────────────────────────────────────────────────
INSERT IGNORE INTO Roles (name, description) VALUES
('manager',  'Full system access'),
('chef',     'Kitchen staff'),
('employee', 'General staff'),
('supplier', 'Ingredient supplier'),
('customer', 'Restaurant customer');

-- ── Users (password = "password123" for all) ─────────────────────────────────
-- bcrypt hash of "password123" (passlib[bcrypt]==1.7.4 / bcrypt==4.0.1)
SET @hash = '$2b$12$BEW87UjUenLX.gdZdi8ikepW5agUAJpEMqbRLn/tP1z8/RwyTUdri';

INSERT IGNORE INTO Users (username, email, password_hash, last_login, role_id) VALUES
('admin',        'admin@smartplate.com',    @hash, NOW(), (SELECT role_id FROM Roles WHERE name='manager')),
('chef_ali',     'ali@smartplate.com',      @hash, NOW(), (SELECT role_id FROM Roles WHERE name='chef')),
('chef_priya',   'priya@smartplate.com',    @hash, NOW(), (SELECT role_id FROM Roles WHERE name='chef')),
('emp_raj',      'raj@smartplate.com',      @hash, NOW(), (SELECT role_id FROM Roles WHERE name='employee')),
('sup_freshco',  'fresh@freshco.com',       @hash, NOW(), (SELECT role_id FROM Roles WHERE name='supplier')),
('sup_quicksup', 'quick@quicksupply.com',   @hash, NOW(), (SELECT role_id FROM Roles WHERE name='supplier')),
('customer_sara','sara@email.com',          @hash, NOW(), (SELECT role_id FROM Roles WHERE name='customer')),
('customer_john','john@email.com',          @hash, NOW(), (SELECT role_id FROM Roles WHERE name='customer'));

-- ── Employees ────────────────────────────────────────────────────────────────
INSERT IGNORE INTO Employees (hire_date, salary, user_id) VALUES
(NOW(), 0,        (SELECT user_id FROM Users WHERE username='admin')),
(NOW(), 55000.00, (SELECT user_id FROM Users WHERE username='chef_ali')),
(NOW(), 52000.00, (SELECT user_id FROM Users WHERE username='chef_priya')),
(NOW(), 38000.00, (SELECT user_id FROM Users WHERE username='emp_raj'));

-- ── Customers ─────────────────────────────────────────────────────────────────
INSERT IGNORE INTO Customers (name, visit_frequency, user_id) VALUES
('Sara Ahmed', 5, (SELECT user_id FROM Users WHERE username='customer_sara')),
('John Smith', 2, (SELECT user_id FROM Users WHERE username='customer_john'));

-- ── Suppliers ────────────────────────────────────────────────────────────────
INSERT IGNORE INTO Suppliers (name, contact, delivery_time, is_active, user_id) VALUES
('FreshCo Produce',  'fresh@freshco.com',     2, 1, (SELECT user_id FROM Users WHERE username='sup_freshco')),
('QuickSupply Ltd.', 'quick@quicksupply.com', 1, 1, (SELECT user_id FROM Users WHERE username='sup_quicksup'));

-- ── Ingredients ──────────────────────────────────────────────────────────────
INSERT IGNORE INTO Ingredients (name, unit, min_stock, quantity, allergen_id) VALUES
('Tomato',        'kg',    5.00, 20.00, (SELECT allergen_id FROM Allergens WHERE name='None')),
('Flour',         'kg',   10.00, 40.00, (SELECT allergen_id FROM Allergens WHERE name='Gluten')),
('Mozzarella',    'kg',    3.00, 12.00, (SELECT allergen_id FROM Allergens WHERE name='Dairy')),
('Olive Oil',     'litre', 2.00,  8.00, (SELECT allergen_id FROM Allergens WHERE name='None')),
('Chicken',       'kg',    4.00, 15.00, (SELECT allergen_id FROM Allergens WHERE name='None')),
('Rice',          'kg',    5.00, 25.00, (SELECT allergen_id FROM Allergens WHERE name='None')),
('Eggs',          'units', 24.0, 60.00, (SELECT allergen_id FROM Allergens WHERE name='Eggs')),
('Butter',        'kg',    1.00,  5.00, (SELECT allergen_id FROM Allergens WHERE name='Dairy')),
('Garlic',        'kg',    0.50,  3.00, (SELECT allergen_id FROM Allergens WHERE name='None')),
('Pasta',         'kg',    3.00, 12.00, (SELECT allergen_id FROM Allergens WHERE name='Gluten'));

-- ── Supplies (supplier -> ingredient + pricing) ───────────────────────────────
INSERT IGNORE INTO Supplies (supplier_id, ingredient_id, price_per_unit, unit) VALUES
(1, 1, 1.20, 'kg'),   -- FreshCo -> Tomato
(1, 3, 8.50, 'kg'),   -- FreshCo -> Mozzarella
(1, 4, 6.00, 'litre'),-- FreshCo -> Olive Oil
(1, 5, 5.50, 'kg'),   -- FreshCo -> Chicken
(1, 6, 0.80, 'kg'),   -- FreshCo -> Rice
(1, 9, 2.00, 'kg'),   -- FreshCo -> Garlic
(2, 2, 0.60, 'kg'),   -- QuickSupply -> Flour
(2, 7, 0.25, 'units'),-- QuickSupply -> Eggs
(2, 8, 7.00, 'kg'),   -- QuickSupply -> Butter
(2, 10,1.20, 'kg');   -- QuickSupply -> Pasta

-- ── Inventory Batches (delivered stock) ──────────────────────────────────────
INSERT IGNORE INTO Inventory_Batches (purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id) VALUES
(DATE_SUB(NOW(),INTERVAL 3 DAY), DATE_ADD(NOW(),INTERVAL 14 DAY), 20.00,'kg',   24.00, 2, 1, 1),
(DATE_SUB(NOW(),INTERVAL 2 DAY), DATE_ADD(NOW(),INTERVAL 30 DAY), 40.00,'kg',   24.00, 2, 2, 2),
(DATE_SUB(NOW(),INTERVAL 4 DAY), DATE_ADD(NOW(),INTERVAL 7  DAY), 12.00,'kg',  102.00, 2, 1, 3),
(DATE_SUB(NOW(),INTERVAL 1 DAY), DATE_ADD(NOW(),INTERVAL 60 DAY),  8.00,'litre',48.00, 2, 1, 4),
(DATE_SUB(NOW(),INTERVAL 2 DAY), DATE_ADD(NOW(),INTERVAL 5  DAY), 15.00,'kg',   82.50, 2, 1, 5),
(DATE_SUB(NOW(),INTERVAL 5 DAY), DATE_ADD(NOW(),INTERVAL 90 DAY), 25.00,'kg',   20.00, 2, 1, 6),
(DATE_SUB(NOW(),INTERVAL 1 DAY), DATE_ADD(NOW(),INTERVAL 10 DAY), 60.00,'units',15.00, 2, 2, 7),
(DATE_SUB(NOW(),INTERVAL 3 DAY), DATE_ADD(NOW(),INTERVAL 20 DAY),  5.00,'kg',   35.00, 2, 2, 8),
(DATE_SUB(NOW(),INTERVAL 2 DAY), DATE_ADD(NOW(),INTERVAL 21 DAY),  3.00,'kg',    6.00, 2, 1, 9),
(DATE_SUB(NOW(),INTERVAL 1 DAY), DATE_ADD(NOW(),INTERVAL 30 DAY), 12.00,'kg',   14.40, 2, 2, 10);

-- ── Categories & Menu Items ───────────────────────────────────────────────────
INSERT IGNORE INTO Category (name) VALUES ('Pizza'), ('Pasta'), ('Mains'), ('Sides'), ('Desserts');

CALL sp_AddMenuItem('Margherita Pizza',    'Classic tomato and mozzarella',      12.99, 15, 'Pizza');
CALL sp_AddMenuItem('Chicken Tikka Pizza', 'Spicy chicken with tomato base',     14.99, 18, 'Pizza');
CALL sp_AddMenuItem('Spaghetti Bolognese', 'Pasta with rich meat sauce',         13.99, 20, 'Pasta');
CALL sp_AddMenuItem('Grilled Chicken',     'Herb marinated grilled chicken',     15.99, 25, 'Mains');
CALL sp_AddMenuItem('Fried Rice',          'Wok fried rice with vegetables',     10.99, 15, 'Mains');
CALL sp_AddMenuItem('Garlic Bread',        'Toasted bread with garlic butter',    4.99, 8,  'Sides');

-- ── Recipes ───────────────────────────────────────────────────────────────────
-- Margherita Pizza (item 1): Tomato, Mozzarella, Flour, Olive Oil
CALL sp_AddRecipeLine(1, 1, 0.20, 'kg');
CALL sp_AddRecipeLine(1, 3, 0.15, 'kg');
CALL sp_AddRecipeLine(1, 2, 0.30, 'kg');
CALL sp_AddRecipeLine(1, 4, 0.05, 'litre');
-- Chicken Tikka Pizza (item 2): Tomato, Mozzarella, Flour, Chicken
CALL sp_AddRecipeLine(2, 1, 0.15, 'kg');
CALL sp_AddRecipeLine(2, 3, 0.15, 'kg');
CALL sp_AddRecipeLine(2, 2, 0.30, 'kg');
CALL sp_AddRecipeLine(2, 5, 0.20, 'kg');
-- Spaghetti Bolognese (item 3): Pasta, Tomato, Garlic, Olive Oil
CALL sp_AddRecipeLine(3, 10, 0.20, 'kg');
CALL sp_AddRecipeLine(3, 1,  0.10, 'kg');
CALL sp_AddRecipeLine(3, 9,  0.02, 'kg');
CALL sp_AddRecipeLine(3, 4,  0.03, 'litre');
-- Grilled Chicken (item 4): Chicken, Garlic, Olive Oil
CALL sp_AddRecipeLine(4, 5, 0.30, 'kg');
CALL sp_AddRecipeLine(4, 9, 0.01, 'kg');
CALL sp_AddRecipeLine(4, 4, 0.02, 'litre');
-- Fried Rice (item 5): Rice, Eggs, Garlic
CALL sp_AddRecipeLine(5, 6, 0.25, 'kg');
CALL sp_AddRecipeLine(5, 7, 2.00, 'units');
CALL sp_AddRecipeLine(5, 9, 0.01, 'kg');
-- Garlic Bread (item 6): Flour, Butter, Garlic
CALL sp_AddRecipeLine(6, 2, 0.10, 'kg');
CALL sp_AddRecipeLine(6, 8, 0.05, 'kg');
CALL sp_AddRecipeLine(6, 9, 0.01, 'kg');

-- ── Occasions ─────────────────────────────────────────────────────────────────
INSERT IGNORE INTO Occasions (name) VALUES ('Regular');

-- ── Compliance Records (0=waiting, 1=passed, 2=failed) ──────────────────────
CALL sp_LogCompliance(1, 'Monthly kitchen hygiene inspection - passed');
CALL sp_LogCompliance(1, 'Food safety audit - passed');
CALL sp_LogCompliance(0, 'Equipment check - awaiting inspection');

-- ── Weather Data ──────────────────────────────────────────────────────────────
CALL sp_RecordWeather(DATE_SUB(NOW(),INTERVAL 2 DAY), 28.50, 65.00);
CALL sp_RecordWeather(DATE_SUB(NOW(),INTERVAL 1 DAY), 26.00, 70.00);
CALL sp_RecordWeather(NOW(), 24.50, 68.00);

SELECT 'Dummy data loaded successfully' AS status;
