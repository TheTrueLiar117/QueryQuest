-- =====================================================================
-- QueryQuest :: Quick-Commerce  ::  03_queries.sql
-- Analytical / reporting queries. Each is a self-contained "business
-- question" and shows off a specific SQL technique (join, subquery,
-- GROUP BY, HAVING, window function, CTE, set op, etc.).
--
-- Run any single query on its own. Comments explain the technique and,
-- where relevant, the alternative you could have written instead.
-- =====================================================================
SET search_path TO qcommerce;

-- ---------------------------------------------------------------------
-- Q1. Basic INNER JOIN: list delivered orders with the customer's name
--     and the store they were fulfilled from.
-- Technique: two-table INNER JOIN + WHERE filter.
-- ---------------------------------------------------------------------
SELECT o.order_id, u.full_name, s.store_name, o.placed_at::date AS order_date
FROM orders o
JOIN users  u ON u.user_id  = o.user_id
JOIN stores s ON s.store_id = o.store_id
WHERE o.status = 'delivered'
ORDER BY o.placed_at;

-- ---------------------------------------------------------------------
-- Q2. Order value via GROUP BY: total value of each order from its lines.
-- Technique: aggregate SUM(qty*price) grouped by the order.
-- Note: we intentionally recompute from order_items (source of truth)
--       instead of trusting payments.amount.
-- ---------------------------------------------------------------------
SELECT o.order_id,
       o.status,
       SUM(oi.quantity * oi.unit_price) AS order_value
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.status
ORDER BY order_value DESC;

-- ---------------------------------------------------------------------
-- Q3. HAVING: which customers have spent more than Rs.500 in total on
--     DELIVERED orders? (HAVING filters *after* aggregation.)
-- Technique: JOIN chain + GROUP BY + HAVING.
-- WHY HAVING not WHERE: WHERE filters rows before grouping; you cannot
--     put SUM() in a WHERE. HAVING is the post-aggregate filter.
-- ---------------------------------------------------------------------
SELECT u.user_id, u.full_name,
       SUM(oi.quantity * oi.unit_price) AS total_spent
FROM users u
JOIN orders o       ON o.user_id  = u.user_id AND o.status = 'delivered'
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY u.user_id, u.full_name
HAVING SUM(oi.quantity * oi.unit_price) > 500
ORDER BY total_spent DESC;

-- ---------------------------------------------------------------------
-- Q4. LEFT JOIN to find the "zero" case: users who have never ordered.
-- Technique: LEFT JOIN + IS NULL anti-join pattern.
-- WHY LEFT JOIN + IS NULL: an INNER JOIN would drop the very users we
--     want. LEFT JOIN keeps them; the unmatched side is NULL, so
--     "o.order_id IS NULL" isolates the non-orderers.
-- ---------------------------------------------------------------------
SELECT u.user_id, u.full_name
FROM users u
LEFT JOIN orders o ON o.user_id = u.user_id
WHERE o.order_id IS NULL;

-- ---------------------------------------------------------------------
-- Q5. Correlated subquery: products priced above the average price
--     within their OWN category.
-- Technique: correlated scalar subquery (inner query references outer p1).
-- Alternative: a window function AVG(...) OVER (PARTITION BY category)
--     (shown in Q10) — usually faster. Correlated subquery shown here
--     because interviewers love to test that you understand it.
-- ---------------------------------------------------------------------
SELECT p1.product_name, c.category_name, p1.mrp
FROM products p1
JOIN categories c ON c.category_id = p1.category_id
WHERE p1.mrp > (
    SELECT AVG(p2.mrp)
    FROM products p2
    WHERE p2.category_id = p1.category_id   -- correlation to outer row
)
ORDER BY c.category_name, p1.mrp DESC;

-- ---------------------------------------------------------------------
-- Q6. Subquery with IN: products that are currently OUT OF STOCK in at
--     least one store.
-- Technique: IN (subquery). EXISTS is the common alternative.
-- ---------------------------------------------------------------------
SELECT product_id, product_name
FROM products
WHERE product_id IN (
    SELECT product_id FROM inventory WHERE quantity = 0
);

-- ---------------------------------------------------------------------
-- Q7. Top-selling products: units sold + revenue, best first.
-- Technique: JOIN + GROUP BY + ORDER BY + LIMIT.
-- ---------------------------------------------------------------------
SELECT p.product_name,
       SUM(oi.quantity)                    AS units_sold,
       SUM(oi.quantity * oi.unit_price)    AS revenue
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id AND o.status <> 'cancelled'
JOIN products p ON p.product_id = oi.product_id
GROUP BY p.product_name
ORDER BY units_sold DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- Q8. Revenue per store, per city (multi-level GROUP BY).
-- Technique: GROUP BY on two dimensions.
-- ---------------------------------------------------------------------
SELECT s.city, s.store_name,
       COUNT(DISTINCT o.order_id)          AS num_orders,
       SUM(oi.quantity * oi.unit_price)    AS revenue
FROM stores s
JOIN orders o       ON o.store_id  = s.store_id AND o.status = 'delivered'
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY s.city, s.store_name
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------
-- Q9. Delivery performance: average delivery time per partner, and how
--     many deliveries they completed. HAVING keeps only finished ones.
-- Technique: timestamp subtraction -> INTERVAL, aggregate to minutes.
-- ---------------------------------------------------------------------
SELECT dp.full_name,
       COUNT(*)                                                   AS completed,
       ROUND(AVG(EXTRACT(EPOCH FROM (d.delivered_at - d.assigned_at))/60), 1)
                                                                  AS avg_minutes
FROM deliveries d
JOIN delivery_partners dp ON dp.partner_id = d.partner_id
WHERE d.delivered_at IS NOT NULL
GROUP BY dp.full_name
ORDER BY avg_minutes;

-- ---------------------------------------------------------------------
-- Q10. Window functions: rank each product by revenue WITHIN its category,
--      without collapsing rows.
-- Technique: RANK() OVER (PARTITION BY ... ORDER BY ...) + CTE.
-- WHY a window fn over GROUP BY: GROUP BY collapses to one row per group;
--      a window keeps every row but adds the ranking alongside it.
-- ---------------------------------------------------------------------
WITH product_rev AS (
    SELECT p.product_id, p.product_name, c.category_name,
           COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS revenue
    FROM products p
    JOIN categories c   ON c.category_id = p.category_id
    LEFT JOIN order_items oi ON oi.product_id = p.product_id
    LEFT JOIN orders o       ON o.order_id = oi.order_id AND o.status <> 'cancelled'
    GROUP BY p.product_id, p.product_name, c.category_name
)
SELECT category_name, product_name, revenue,
       RANK() OVER (PARTITION BY category_name ORDER BY revenue DESC) AS rank_in_category
FROM product_rev
ORDER BY category_name, rank_in_category;

-- ---------------------------------------------------------------------
-- Q11. Daily revenue trend with a running total.
-- Technique: GROUP BY day + SUM() OVER (ORDER BY day) window running total.
-- ---------------------------------------------------------------------
SELECT o.placed_at::date AS day,
       SUM(oi.quantity * oi.unit_price) AS daily_revenue,
       SUM(SUM(oi.quantity * oi.unit_price)) OVER (ORDER BY o.placed_at::date)
                                              AS running_total
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status <> 'cancelled'
GROUP BY o.placed_at::date
ORDER BY day;

-- ---------------------------------------------------------------------
-- Q12. EXISTS: stores that have EVER fulfilled an order (vs. dead stores).
-- Technique: EXISTS correlated subquery. Stops at first match -> efficient.
-- ---------------------------------------------------------------------
SELECT s.store_id, s.store_name
FROM stores s
WHERE EXISTS (
    SELECT 1 FROM orders o WHERE o.store_id = s.store_id
);

-- ---------------------------------------------------------------------
-- Q13. Set operation: products that are sold in Kanpur stores but NOT in
--      Bengaluru stores (inventory-wise).
-- Technique: EXCEPT.
-- ---------------------------------------------------------------------
SELECT i.product_id FROM inventory i JOIN stores s ON s.store_id=i.store_id WHERE s.city='Kanpur'
EXCEPT
SELECT i.product_id FROM inventory i JOIN stores s ON s.store_id=i.store_id WHERE s.city='Bengaluru';

-- ---------------------------------------------------------------------
-- Q14. CASE + conditional aggregation: order status breakdown per store
--      as columns (a mini pivot table).
-- Technique: SUM(CASE WHEN ... THEN 1 ELSE 0 END).
-- ---------------------------------------------------------------------
SELECT s.store_name,
       SUM(CASE WHEN o.status='delivered'        THEN 1 ELSE 0 END) AS delivered,
       SUM(CASE WHEN o.status='cancelled'        THEN 1 ELSE 0 END) AS cancelled,
       SUM(CASE WHEN o.status='out_for_delivery' THEN 1 ELSE 0 END) AS in_transit,
       SUM(CASE WHEN o.status='placed'           THEN 1 ELSE 0 END) AS placed
FROM stores s
LEFT JOIN orders o ON o.store_id = s.store_id
GROUP BY s.store_name
ORDER BY s.store_name;

-- ---------------------------------------------------------------------
-- Q15. Repeat customers: users with more than one non-cancelled order,
--      plus their average order value (subquery-in-FROM / derived table).
-- Technique: derived table (subquery in FROM) then aggregate.
-- ---------------------------------------------------------------------
SELECT t.full_name,
       COUNT(*)             AS num_orders,
       ROUND(AVG(t.order_value), 2) AS avg_order_value
FROM (
    SELECT o.order_id, u.full_name,
           SUM(oi.quantity * oi.unit_price) AS order_value
    FROM users u
    JOIN orders o       ON o.user_id  = u.user_id AND o.status <> 'cancelled'
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.order_id, u.full_name
) t
GROUP BY t.full_name
HAVING COUNT(*) > 1
ORDER BY num_orders DESC, avg_order_value DESC;
