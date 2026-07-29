-- =====================================================================
-- QueryQuest :: Quick-Commerce Platform  ::  01_schema.sql
-- PostgreSQL 16
--
-- Core domain: a Blinkit/Zepto-style quick-commerce app. Customers place
-- orders from nearby "dark stores"; a delivery partner fulfils each order.
--
-- The four entities the project brief names explicitly (users, inventory,
-- orders, deliveries) are the spine of the schema. The rest exist to keep
-- the model in a clean normal form (no repeating groups, no derivable data
-- stored twice).
--
-- Every design choice worth defending in an interview is tagged  >>> WHY.
-- =====================================================================

-- Start clean so the script is re-runnable (idempotent).
DROP SCHEMA IF EXISTS qcommerce CASCADE;
CREATE SCHEMA qcommerce;
SET search_path TO qcommerce;

-- =====================================================================
-- 1. USERS
-- =====================================================================
CREATE TABLE users (
    user_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     TEXT        NOT NULL,
    email         TEXT        NOT NULL,
    phone         TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_users_email UNIQUE (email),   -- >>> WHY: no two accounts share an email
    CONSTRAINT uq_users_phone UNIQUE (phone)    -- >>> WHY: phone is the login handle in India-style apps
);
-- >>> WHY IDENTITY over SERIAL: GENERATED ALWAYS AS IDENTITY is the SQL-standard
--     way (Postgres 10+). SERIAL is legacy and leaks an implicit sequence you
--     can accidentally write to. Both give an auto-incrementing surrogate key.
-- >>> WHY a surrogate key at all: email/phone *could* be natural keys, but they
--     change (people switch numbers). A meaningless integer PK never changes,
--     so foreign keys pointing at it never have to cascade an update.

-- =====================================================================
-- 2. ADDRESSES  (a user can save many; an order ships to exactly one)
-- =====================================================================
CREATE TABLE addresses (
    address_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       INT         NOT NULL,
    line1         TEXT        NOT NULL,
    city          TEXT        NOT NULL,
    pincode       TEXT        NOT NULL,
    latitude      NUMERIC(9,6),
    longitude     NUMERIC(9,6),
    CONSTRAINT fk_addr_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE CASCADE
    -- >>> WHY CASCADE: an address has no meaning without its owner. Delete the
    --     user -> their saved addresses are junk, so they go too.
);

-- =====================================================================
-- 3. STORES  (dark stores / fulfilment hubs)
-- =====================================================================
CREATE TABLE stores (
    store_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_name    TEXT        NOT NULL,
    city          TEXT        NOT NULL,
    pincode       TEXT        NOT NULL,
    is_active     BOOLEAN     NOT NULL DEFAULT TRUE
);

-- =====================================================================
-- 4. CATEGORIES  &  PRODUCTS
-- =====================================================================
CREATE TABLE categories (
    category_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name TEXT NOT NULL,
    CONSTRAINT uq_category_name UNIQUE (category_name)
);

CREATE TABLE products (
    product_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_name  TEXT          NOT NULL,
    category_id   INT           NOT NULL,
    mrp           NUMERIC(10,2) NOT NULL CHECK (mrp >= 0),
    -- >>> WHY NUMERIC not FLOAT for money: FLOAT is binary floating point, so
    --     0.1 + 0.2 != 0.3. Never store currency in it. NUMERIC(10,2) is exact.
    CONSTRAINT fk_prod_cat FOREIGN KEY (category_id)
        REFERENCES categories (category_id) ON DELETE RESTRICT
    -- >>> WHY RESTRICT: you should not be able to delete a category that still
    --     has products hanging off it. Force the caller to deal with them first.
);

-- =====================================================================
-- 5. INVENTORY  (how much of each product each store holds)
-- =====================================================================
CREATE TABLE inventory (
    store_id      INT           NOT NULL,
    product_id    INT           NOT NULL,
    quantity      INT           NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    price         NUMERIC(10,2) NOT NULL CHECK (price >= 0),  -- selling price at this store
    PRIMARY KEY (store_id, product_id),      -- >>> WHY composite PK: one row per
                                             --     (store, product) pair, guaranteed
                                             --     unique. No surrogate needed here
                                             --     because the pair *is* the identity.
    CONSTRAINT fk_inv_store   FOREIGN KEY (store_id)   REFERENCES stores (store_id)     ON DELETE CASCADE,
    CONSTRAINT fk_inv_product FOREIGN KEY (product_id) REFERENCES products (product_id) ON DELETE CASCADE
);
-- >>> DESIGN FORK (documented in the prep guide): this is a *snapshot* of stock
--     (one number, current level). The alternative is an append-only "stock
--     ledger" of +/- movements you SUM up. Snapshot = simple + fast reads;
--     ledger = full audit trail. For a query-reporting project, snapshot wins.

-- =====================================================================
-- 6. DELIVERY PARTNERS  (riders)
-- =====================================================================
CREATE TABLE delivery_partners (
    partner_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     TEXT    NOT NULL,
    phone         TEXT    NOT NULL,
    vehicle_type  TEXT    NOT NULL DEFAULT 'bike'
                  CHECK (vehicle_type IN ('bike','scooter','bicycle','ecycle')),
    -- >>> WHY CHECK-list instead of a lookup table: a tiny, rarely-changing set
    --     of values. A CHECK keeps it inline and readable. If the set grew or
    --     needed its own attributes, we'd promote it to a lookup table + FK.
    CONSTRAINT uq_partner_phone UNIQUE (phone)
);

-- =====================================================================
-- 7. ORDERS  (the header) + ORDER_ITEMS (the lines)
-- =====================================================================
CREATE TABLE orders (
    order_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       INT         NOT NULL,
    store_id      INT         NOT NULL,
    address_id    INT         NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'placed'
                  CHECK (status IN ('placed','packed','out_for_delivery','delivered','cancelled')),
    placed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_ord_user    FOREIGN KEY (user_id)    REFERENCES users (user_id)         ON DELETE RESTRICT,
    CONSTRAINT fk_ord_store   FOREIGN KEY (store_id)   REFERENCES stores (store_id)       ON DELETE RESTRICT,
    CONSTRAINT fk_ord_address FOREIGN KEY (address_id) REFERENCES addresses (address_id)  ON DELETE RESTRICT
    -- >>> WHY RESTRICT on orders' parents: orders are financial records. You must
    --     never silently lose one because a parent row was deleted. Deletes of
    --     users/stores with live orders should be blocked, not cascaded.
);

CREATE TABLE order_items (
    order_id      INT           NOT NULL,
    product_id    INT           NOT NULL,
    quantity      INT           NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    -- >>> WHY store unit_price on the line (denormalisation on purpose): the
    --     product price changes over time. An order must remember what the
    --     customer *actually paid*, not today's price. This is a deliberate,
    --     defensible copy — a historical fact, not derivable data.
    PRIMARY KEY (order_id, product_id),   -- one line per product per order
    CONSTRAINT fk_oi_order   FOREIGN KEY (order_id)   REFERENCES orders (order_id)     ON DELETE CASCADE,
    CONSTRAINT fk_oi_product FOREIGN KEY (product_id) REFERENCES products (product_id) ON DELETE RESTRICT
    -- >>> WHY CASCADE from order, RESTRICT from product: deleting an order should
    --     take its lines with it (they're part of it). But you can't delete a
    --     product that appears in historical orders.
);
-- >>> WHY split orders/order_items at all: a single "orders" table with columns
--     product1, product2, ... violates 1NF (repeating groups) and caps basket
--     size. The header/line split is the textbook fix and enables GROUP BY.

-- =====================================================================
-- 8. DELIVERIES  (1-to-1 with an order; who delivered it, when)
-- =====================================================================
CREATE TABLE deliveries (
    delivery_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      INT         NOT NULL,
    partner_id    INT,                       -- NULL until a rider is assigned
    assigned_at   TIMESTAMPTZ,
    delivered_at  TIMESTAMPTZ,
    CONSTRAINT uq_delivery_order UNIQUE (order_id),   -- >>> WHY UNIQUE: enforces
                                                      --     the 1:1 — an order has
                                                      --     at most one delivery.
    CONSTRAINT fk_del_order   FOREIGN KEY (order_id)   REFERENCES orders (order_id)              ON DELETE CASCADE,
    CONSTRAINT fk_del_partner FOREIGN KEY (partner_id) REFERENCES delivery_partners (partner_id) ON DELETE SET NULL,
    -- >>> WHY SET NULL on partner: if a rider leaves the platform, the delivery
    --     record survives (we still want its timestamps for reporting); it just
    --     loses the rider link. The order history is never destroyed.
    CONSTRAINT chk_delivery_time CHECK (delivered_at IS NULL OR delivered_at >= assigned_at)
    -- >>> WHY this CHECK: you can't be delivered before you were assigned. Catches
    --     bad data at write time instead of during a painful report later.
);

-- =====================================================================
-- 9. PAYMENTS  (1-to-1 with an order)
-- =====================================================================
CREATE TABLE payments (
    payment_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      INT           NOT NULL,
    amount        NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    method        TEXT          NOT NULL CHECK (method IN ('upi','card','cod','wallet')),
    paid_at       TIMESTAMPTZ,
    CONSTRAINT uq_payment_order UNIQUE (order_id),
    CONSTRAINT fk_pay_order FOREIGN KEY (order_id) REFERENCES orders (order_id) ON DELETE CASCADE
);

-- =====================================================================
-- Helpful secondary indexes for the read-heavy reporting workload.
-- >>> WHY: PKs are auto-indexed, but FKs are NOT. Queries filter/join on these
--     columns constantly, so we index the ones that carry the join load.
-- =====================================================================
CREATE INDEX idx_orders_user       ON orders (user_id);
CREATE INDEX idx_orders_store      ON orders (store_id);
CREATE INDEX idx_orders_placed_at  ON orders (placed_at);
CREATE INDEX idx_order_items_prod  ON order_items (product_id);
CREATE INDEX idx_inventory_product ON inventory (product_id);
CREATE INDEX idx_deliveries_partner ON deliveries (partner_id);
