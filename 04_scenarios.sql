-- =====================================================================
-- QueryQuest :: 04_scenarios.sql
-- Three extra "querying scenarios" beyond the quick-commerce core, so the
-- project genuinely spans:  employees, banking, food-delivery.
-- Each is a small self-contained schema + seed + a few analytical queries
-- built around the classic SQL patterns those domains are known for.
-- =====================================================================

-- #####################################################################
-- SCENARIO A :: EMPLOYEES  (the classic self-join / department domain)
-- #####################################################################
DROP SCHEMA IF EXISTS hr CASCADE;
CREATE SCHEMA hr;
SET search_path TO hr;

CREATE TABLE departments (
    dept_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dept_name TEXT NOT NULL UNIQUE
);

CREATE TABLE employees (
    emp_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    emp_name   TEXT          NOT NULL,
    dept_id    INT,
    manager_id INT,                              -- self-reference (a manager is an employee)
    salary     NUMERIC(10,2) NOT NULL CHECK (salary >= 0),
    hired_on   DATE          NOT NULL,
    CONSTRAINT fk_emp_dept FOREIGN KEY (dept_id)    REFERENCES departments (dept_id) ON DELETE SET NULL,
    CONSTRAINT fk_emp_mgr  FOREIGN KEY (manager_id) REFERENCES employees   (emp_id)  ON DELETE SET NULL
    -- >>> WHY self-referencing FK: manager_id points back into the same table.
    --     This is *the* reason to know self-joins. SET NULL so removing a
    --     manager doesn't delete their reports.
);

INSERT INTO departments (dept_name) VALUES ('Engineering'),('Sales'),('HR'),('Finance');

INSERT INTO employees (emp_name, dept_id, manager_id, salary, hired_on) VALUES
('Nisha (CEO)',    NULL, NULL, 500000, '2015-01-10'),   -- emp 1, top of tree
('Raghav',         1,    1,    220000, '2017-03-01'),    -- emp 2, eng head
('Sneha',          1,    2,    120000, '2019-06-15'),    -- emp 3
('Vikram',         1,    2,    118000, '2020-01-20'),    -- emp 4
('Anita',          2,    1,    180000, '2018-07-11'),    -- emp 5, sales head
('Farhan',         2,    5,     95000, '2021-02-05'),    -- emp 6
('Meera',          3,    1,    110000, '2019-09-30'),    -- emp 7
('Dev',            4,    1,    140000, '2016-11-25'),    -- emp 8
('Tara',           2,    5,     99000, '2022-08-01');    -- emp 9

-- A1. Self-join: every employee next to their manager's name.
--     Technique: join a table to itself with two aliases; LEFT JOIN keeps
--     the CEO (who has no manager).
SELECT e.emp_name AS employee, m.emp_name AS manager
FROM employees e
LEFT JOIN employees m ON m.emp_id = e.manager_id
ORDER BY e.emp_id;

-- A2. Highest paid employee PER department.
--     Technique: window RANK() partitioned by dept. Filter rank = 1.
WITH ranked AS (
    SELECT e.emp_name, d.dept_name, e.salary,
           RANK() OVER (PARTITION BY e.dept_id ORDER BY e.salary DESC) AS rnk
    FROM employees e JOIN departments d ON d.dept_id = e.dept_id
)
SELECT dept_name, emp_name, salary FROM ranked WHERE rnk = 1 ORDER BY dept_name;

-- A3. Departments whose AVERAGE salary beats the company average.
--     Technique: GROUP BY + HAVING with a scalar subquery as the threshold.
SELECT d.dept_name, ROUND(AVG(e.salary),0) AS avg_salary
FROM employees e JOIN departments d ON d.dept_id = e.dept_id
GROUP BY d.dept_name
HAVING AVG(e.salary) > (SELECT AVG(salary) FROM employees)
ORDER BY avg_salary DESC;

-- A4. Headcount + payroll per department, including empty departments.
--     Technique: LEFT JOIN from departments so a 0-employee dept still shows.
SELECT d.dept_name,
       COUNT(e.emp_id)          AS headcount,
       COALESCE(SUM(e.salary),0) AS payroll
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id
GROUP BY d.dept_name
ORDER BY payroll DESC;


-- #####################################################################
-- SCENARIO B :: BANKING  (accounts / transactions — balances & flows)
-- #####################################################################
DROP SCHEMA IF EXISTS bank CASCADE;
CREATE SCHEMA bank;
SET search_path TO bank;

CREATE TABLE customers (
    cust_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cust_name TEXT NOT NULL,
    city      TEXT NOT NULL
);

CREATE TABLE accounts (
    account_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cust_id      INT           NOT NULL,
    account_type TEXT          NOT NULL CHECK (account_type IN ('savings','current')),
    balance      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    opened_on    DATE          NOT NULL,
    CONSTRAINT fk_acc_cust FOREIGN KEY (cust_id) REFERENCES customers (cust_id) ON DELETE RESTRICT
    -- >>> WHY RESTRICT: never orphan or auto-destroy a financial account by
    --     deleting a customer row. Money records are sacred.
);

CREATE TABLE transactions (
    txn_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id INT           NOT NULL,
    txn_type   TEXT          NOT NULL CHECK (txn_type IN ('deposit','withdrawal')),
    amount     NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    txn_time   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT fk_txn_acc FOREIGN KEY (account_id) REFERENCES accounts (account_id) ON DELETE CASCADE
);
-- >>> DESIGN NOTE: we keep a running 'balance' column AND a transaction log.
--     That's mild denormalisation (balance is derivable by summing txns).
--     Real banks do this for read speed + reconcile the two. The prep guide
--     discusses the pure-ledger alternative.

INSERT INTO customers (cust_name, city) VALUES
('Aarav Sharma','Kanpur'),('Diya Verma','Kanpur'),
('Kabir Mehta','Delhi'),('Ishita Nair','Bengaluru');

INSERT INTO accounts (cust_id, account_type, balance, opened_on) VALUES
(1,'savings', 52000, '2021-04-01'),
(1,'current', 130000,'2022-01-15'),
(2,'savings', 8000,  '2023-06-10'),
(3,'savings', 240000,'2019-02-20'),
(4,'current', 15000, '2024-09-05');

INSERT INTO transactions (account_id, txn_type, amount, txn_time) VALUES
(1,'deposit',   20000, now()-interval '30 days'),
(1,'withdrawal', 5000, now()-interval '20 days'),
(1,'deposit',   10000, now()-interval '5 days'),
(2,'deposit',   50000, now()-interval '15 days'),
(2,'withdrawal',12000, now()-interval '3 days'),
(3,'deposit',    3000, now()-interval '10 days'),
(4,'deposit',  200000, now()-interval '25 days'),
(4,'withdrawal',30000, now()-interval '2 days'),
(4,'deposit',   40000, now()-interval '1 day');

-- B1. Net flow per account: deposits minus withdrawals.
--     Technique: conditional aggregation with FILTER (cleaner than CASE).
SELECT a.account_id, c.cust_name, a.account_type,
       SUM(t.amount) FILTER (WHERE t.txn_type='deposit')    AS total_deposits,
       SUM(t.amount) FILTER (WHERE t.txn_type='withdrawal') AS total_withdrawals,
       COALESCE(SUM(t.amount) FILTER (WHERE t.txn_type='deposit'),0)
       - COALESCE(SUM(t.amount) FILTER (WHERE t.txn_type='withdrawal'),0) AS net_flow
FROM accounts a
JOIN customers c ON c.cust_id = a.cust_id
LEFT JOIN transactions t ON t.account_id = a.account_id
GROUP BY a.account_id, c.cust_name, a.account_type
ORDER BY net_flow DESC;

-- B2. Total balance a customer holds across ALL their accounts, and flag
--     high-value customers (> Rs.1,00,000).
--     Technique: GROUP BY customer + CASE label + HAVING-style filter.
SELECT c.cust_name,
       COUNT(a.account_id)      AS num_accounts,
       SUM(a.balance)           AS total_balance,
       CASE WHEN SUM(a.balance) > 100000 THEN 'HIGH VALUE' ELSE 'standard' END AS tier
FROM customers c
JOIN accounts a ON a.cust_id = c.cust_id
GROUP BY c.cust_name
ORDER BY total_balance DESC;

-- B3. Latest transaction per account.
--     Technique: window ROW_NUMBER() partitioned by account, ordered by time.
WITH numbered AS (
    SELECT t.*, ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY txn_time DESC) AS rn
    FROM transactions t
)
SELECT account_id, txn_type, amount, txn_time
FROM numbered WHERE rn = 1 ORDER BY account_id;

-- B4. Accounts with a withdrawal larger than the average withdrawal.
--     Technique: subquery in WHERE returning a scalar.
SELECT DISTINCT a.account_id, c.cust_name
FROM transactions t
JOIN accounts a  ON a.account_id = t.account_id
JOIN customers c ON c.cust_id    = a.cust_id
WHERE t.txn_type='withdrawal'
  AND t.amount > (SELECT AVG(amount) FROM transactions WHERE txn_type='withdrawal');


-- #####################################################################
-- SCENARIO C :: FOOD DELIVERY  (restaurants / menu / orders / ratings)
-- #####################################################################
DROP SCHEMA IF EXISTS food CASCADE;
CREATE SCHEMA food;
SET search_path TO food;

CREATE TABLE restaurants (
    rest_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rest_name TEXT NOT NULL,
    cuisine   TEXT NOT NULL,
    city      TEXT NOT NULL
);

CREATE TABLE menu_items (
    item_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rest_id   INT           NOT NULL,
    item_name TEXT          NOT NULL,
    price     NUMERIC(8,2)  NOT NULL CHECK (price >= 0),
    is_veg    BOOLEAN       NOT NULL,
    CONSTRAINT fk_item_rest FOREIGN KEY (rest_id) REFERENCES restaurants (rest_id) ON DELETE CASCADE
);

CREATE TABLE food_orders (
    forder_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rest_id   INT         NOT NULL,
    cust_name TEXT        NOT NULL,
    order_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    rating    INT         CHECK (rating BETWEEN 1 AND 5),   -- NULL if unrated
    CONSTRAINT fk_forder_rest FOREIGN KEY (rest_id) REFERENCES restaurants (rest_id) ON DELETE RESTRICT
);

CREATE TABLE food_order_items (
    forder_id INT NOT NULL,
    item_id   INT NOT NULL,
    quantity  INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (forder_id, item_id),
    CONSTRAINT fk_foi_order FOREIGN KEY (forder_id) REFERENCES food_orders (forder_id) ON DELETE CASCADE,
    CONSTRAINT fk_foi_item  FOREIGN KEY (item_id)   REFERENCES menu_items  (item_id)   ON DELETE RESTRICT
);

INSERT INTO restaurants (rest_name, cuisine, city) VALUES
('Spice Villa','North Indian','Kanpur'),
('Dragon Bowl','Chinese','Kanpur'),
('Green Leaf','South Indian','Bengaluru'),
('Pizza Point','Italian','Bengaluru');

INSERT INTO menu_items (rest_id, item_name, price, is_veg) VALUES
(1,'Paneer Butter Masala',260,TRUE),(1,'Butter Naan',45,TRUE),(1,'Chicken Curry',320,FALSE),
(2,'Veg Hakka Noodles',180,TRUE),(2,'Chilli Chicken',240,FALSE),
(3,'Masala Dosa',120,TRUE),(3,'Idli Sambar',90,TRUE),
(4,'Margherita Pizza',300,TRUE),(4,'Pepperoni Pizza',380,FALSE);

INSERT INTO food_orders (rest_id, cust_name, order_time, rating) VALUES
(1,'Aarav', now()-interval '9 days', 5),
(1,'Diya',  now()-interval '6 days', 4),
(2,'Kabir', now()-interval '5 days', 3),
(1,'Rohan', now()-interval '4 days', 5),
(3,'Ishita',now()-interval '3 days', 4),
(4,'Sara',  now()-interval '2 days', 2),
(2,'Aarav', now()-interval '1 day',  NULL),   -- unrated
(3,'Diya',  now()-interval '12 hours', 5);

INSERT INTO food_order_items (forder_id, item_id, quantity) VALUES
(1,1,1),(1,2,2),
(2,1,1),(2,3,1),
(3,4,2),(3,5,1),
(4,1,2),(4,2,3),
(5,6,2),(5,7,1),
(6,8,1),(6,9,1),
(7,4,1),
(8,6,1),(8,7,2);

-- C1. Average rating per restaurant, ordered best first; only rated orders.
--     Technique: AVG with NULLs auto-ignored + ROUND + ORDER BY.
SELECT r.rest_name, r.cuisine,
       ROUND(AVG(fo.rating),2) AS avg_rating,
       COUNT(fo.rating)        AS num_ratings
FROM restaurants r
JOIN food_orders fo ON fo.rest_id = r.rest_id
GROUP BY r.rest_name, r.cuisine
HAVING COUNT(fo.rating) > 0
ORDER BY avg_rating DESC;

-- C2. Revenue per restaurant (join across order -> items -> menu price).
--     Technique: 3-table join + GROUP BY.
SELECT r.rest_name,
       SUM(foi.quantity * mi.price) AS revenue
FROM restaurants r
JOIN food_orders fo      ON fo.rest_id   = r.rest_id
JOIN food_order_items foi ON foi.forder_id = fo.forder_id
JOIN menu_items mi       ON mi.item_id   = foi.item_id
GROUP BY r.rest_name
ORDER BY revenue DESC;

-- C3. Most popular item (by units sold) overall.
--     Technique: GROUP BY item + ORDER BY SUM DESC + LIMIT.
SELECT mi.item_name, SUM(foi.quantity) AS units
FROM food_order_items foi
JOIN menu_items mi ON mi.item_id = foi.item_id
GROUP BY mi.item_name
ORDER BY units DESC
LIMIT 3;

-- C4. Restaurants with NO orders yet (LEFT JOIN anti-join), plus every
--     restaurant's order count.
SELECT r.rest_name, COUNT(fo.forder_id) AS num_orders
FROM restaurants r
LEFT JOIN food_orders fo ON fo.rest_id = r.rest_id
GROUP BY r.rest_name
ORDER BY num_orders DESC;

-- C5. Share of veg vs non-veg items sold per city.
--     Technique: join to bring in city + is_veg, conditional aggregation.
SELECT r.city,
       SUM(foi.quantity) FILTER (WHERE mi.is_veg)     AS veg_units,
       SUM(foi.quantity) FILTER (WHERE NOT mi.is_veg) AS nonveg_units
FROM food_order_items foi
JOIN menu_items mi   ON mi.item_id = foi.item_id
JOIN restaurants r   ON r.rest_id  = mi.rest_id
GROUP BY r.city
ORDER BY r.city;
