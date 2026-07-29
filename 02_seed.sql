-- =====================================================================
-- QueryQuest :: Quick-Commerce  ::  02_seed.sql
-- Sample data sized so every analytical query returns something interesting
-- (some big spenders, some zero-order users, some out-of-stock items,
--  some late deliveries, some cancelled orders).
-- =====================================================================
SET search_path TO qcommerce;

-- ---- Users -----------------------------------------------------------
INSERT INTO users (full_name, email, phone) VALUES
('Aarav Sharma',   'aarav@example.com',   '9000000001'),
('Diya Verma',     'diya@example.com',    '9000000002'),
('Kabir Mehta',    'kabir@example.com',   '9000000003'),
('Ishita Nair',    'ishita@example.com',  '9000000004'),
('Rohan Gupta',    'rohan@example.com',   '9000000005'),
('Sara Khan',      'sara@example.com',    '9000000006');  -- never orders (edge case)

-- ---- Addresses -------------------------------------------------------
INSERT INTO addresses (user_id, line1, city, pincode, latitude, longitude) VALUES
(1, 'IIT Kanpur Hall 5',  'Kanpur',    '208016', 26.512, 80.233),
(2, 'Swaroop Nagar',      'Kanpur',    '208002', 26.478, 80.349),
(3, 'Civil Lines',        'Kanpur',    '208001', 26.470, 80.350),
(4, 'Koramangala',        'Bengaluru', '560034', 12.935, 77.626),
(5, 'Indiranagar',        'Bengaluru', '560038', 12.971, 77.640);

-- ---- Stores ----------------------------------------------------------
INSERT INTO stores (store_name, city, pincode, is_active) VALUES
('QuickHub Kanpur-1',    'Kanpur',    '208016', TRUE),
('QuickHub Kanpur-2',    'Kanpur',    '208001', TRUE),
('QuickHub Bengaluru-1', 'Bengaluru', '560034', TRUE),
('QuickHub Bengaluru-2', 'Bengaluru', '560038', FALSE); -- inactive (edge case)

-- ---- Categories ------------------------------------------------------
INSERT INTO categories (category_name) VALUES
('Beverages'), ('Snacks'), ('Dairy'), ('Fruits'), ('Personal Care');

-- ---- Products --------------------------------------------------------
INSERT INTO products (product_name, category_id, mrp) VALUES
('Cola 500ml',        1, 40.00),
('Orange Juice 1L',   1, 110.00),
('Potato Chips',      2, 30.00),
('Choco Cookies',     2, 60.00),
('Milk 1L',           3, 66.00),
('Paneer 200g',       3, 90.00),
('Bananas 1dz',       4, 50.00),
('Apples 1kg',        4, 180.00),
('Shampoo 340ml',     5, 250.00),
('Toothpaste 100g',   5, 95.00);

-- ---- Inventory (store x product) ------------------------------------
-- Kanpur-1 stocks most things; a couple are out of stock (qty 0).
INSERT INTO inventory (store_id, product_id, quantity, price) VALUES
(1, 1, 120, 38.00), (1, 2, 40, 105.00), (1, 3, 200, 28.00),
(1, 4, 0,   58.00),                                  -- out of stock
(1, 5, 80,  64.00), (1, 6, 25, 88.00), (1, 7, 60, 48.00),
(1, 8, 15, 175.00), (1, 9, 30, 240.00), (1,10, 50, 92.00),
-- Kanpur-2
(2, 1, 90, 39.00), (2, 3, 150, 29.00), (2, 5, 0, 65.00), -- milk out of stock
(2, 7, 40, 49.00), (2, 8, 20, 178.00),
-- Bengaluru-1
(3, 1, 100, 40.00), (3, 2, 60, 108.00), (3, 4, 75, 60.00),
(3, 6, 35, 90.00), (3, 9, 45, 245.00), (3,10, 70, 95.00);

-- ---- Delivery partners ----------------------------------------------
INSERT INTO delivery_partners (full_name, phone, vehicle_type) VALUES
('Suresh Yadav', '9500000001', 'bike'),
('Manoj Kumar',  '9500000002', 'scooter'),
('Priya Das',    '9500000003', 'ecycle'),
('Arjun Reddy',  '9500000004', 'bike');   -- gets no deliveries (edge case)

-- ---- Orders ----------------------------------------------------------
-- Mix of statuses across two cities and several days.
INSERT INTO orders (user_id, store_id, address_id, status, placed_at) VALUES
(1, 1, 1, 'delivered',        now() - interval '10 days'),  -- 1
(1, 1, 1, 'delivered',        now() - interval '7 days'),   -- 2
(2, 1, 2, 'delivered',        now() - interval '6 days'),   -- 3
(3, 2, 3, 'delivered',        now() - interval '5 days'),   -- 4
(4, 3, 4, 'delivered',        now() - interval '4 days'),   -- 5
(5, 3, 5, 'out_for_delivery', now() - interval '2 hours'),  -- 6
(1, 1, 1, 'cancelled',        now() - interval '3 days'),   -- 7  (cancelled)
(2, 1, 2, 'placed',           now() - interval '1 hour'),   -- 8
(4, 3, 4, 'delivered',        now() - interval '1 day'),    -- 9
(3, 2, 3, 'delivered',        now() - interval '12 hours'); -- 10

-- ---- Order items -----------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 4, 38.00), (1, 3, 2, 28.00), (1, 5, 1, 64.00),
(2, 8, 2, 175.00), (2, 5, 2, 64.00),
(3, 2, 1, 105.00), (3, 4, 3, 58.00),
(4, 1, 6, 39.00), (4, 7, 1, 49.00),
(5, 6, 2, 90.00), (5, 9, 1, 245.00),
(6, 1, 2, 40.00), (6, 10, 1, 95.00),
(7, 3, 5, 28.00),                              -- cancelled order's line
(8, 1, 1, 39.00),
(9, 2, 2, 108.00), (9, 6, 1, 90.00), (9, 10, 2, 95.00),
(10, 1, 3, 39.00), (10, 8, 1, 178.00);

-- ---- Deliveries ------------------------------------------------------
-- Delivered orders get finished deliveries (some slow). Order 6 is mid-flight.
INSERT INTO deliveries (order_id, partner_id, assigned_at, delivered_at) VALUES
(1,  1, now() - interval '10 days' + interval '5 min',  now() - interval '10 days' + interval '18 min'),
(2,  2, now() - interval '7 days'  + interval '4 min',  now() - interval '7 days'  + interval '12 min'),
(3,  1, now() - interval '6 days'  + interval '6 min',  now() - interval '6 days'  + interval '40 min'), -- slow
(4,  3, now() - interval '5 days'  + interval '3 min',  now() - interval '5 days'  + interval '15 min'),
(5,  2, now() - interval '4 days'  + interval '7 min',  now() - interval '4 days'  + interval '22 min'),
(6,  1, now() - interval '90 min',                      NULL),                                          -- in progress
(9,  3, now() - interval '1 day'   + interval '5 min',  now() - interval '1 day'   + interval '11 min'),
(10, 2, now() - interval '12 hours'+ interval '4 min',  now() - interval '12 hours'+ interval '9 min');

-- ---- Payments --------------------------------------------------------
INSERT INTO payments (order_id, amount, method, paid_at) VALUES
(1,  272.00, 'upi',    now() - interval '10 days'),
(2,  478.00, 'card',   now() - interval '7 days'),
(3,  279.00, 'upi',    now() - interval '6 days'),
(4,  283.00, 'cod',    now() - interval '5 days'),
(5,  425.00, 'upi',    now() - interval '4 days'),
(6,  175.00, 'wallet', NULL),                       -- not yet paid (COD-ish)
(9,  491.00, 'card',   now() - interval '1 day'),
(10, 295.00, 'upi',    now() - interval '12 hours');
-- Order 7 cancelled -> no payment. Order 8 just placed -> no payment yet.
