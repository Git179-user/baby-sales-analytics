-- =====================================================================
-- BABY SALES PROJECT — SQL PHASE (MySQL 8.0+, MySQL Workbench)
-- Source: Cleaned Data sheet of Sales_Data_CLEANED_Excel_Native.xlsx
-- Run section by section, in order. Expected results are in comments.
-- =====================================================================
--
-- SCHEMA (star schema, built in section 3)
--   products (product_id PK, product_name, product_type)
--   orders   (order_id PK, order_code, sales_channel, order_date)
--   sales    (sale_id PK, order_id FK, product_id FK, sale_date, ..., total_sales)
--
-- =====================================================================


-- =====================================================================
-- 1. DATABASE + STAGING TABLE
-- =====================================================================
CREATE DATABASE baby_sales CHARACTER SET utf8mb4;
USE baby_sales;

-- raw_sales mirrors the exported CSV one-to-one (20 columns).
-- sale_date stays VARCHAR on purpose: values look like
-- 2020-11-11T01:39:33+03:00 and the import wizard ruins the "T" and offset.
-- order_id / sale_id are BIGINT because they have 13-14 digits.
CREATE TABLE raw_sales (
    order_id           BIGINT,
    sale_id            BIGINT,
    sale_date          VARCHAR(30),
    order_code         VARCHAR(20),
    transaction_type   VARCHAR(30),
    sale_type          VARCHAR(20),
    sales_channel      VARCHAR(30),
    product_type_raw   VARCHAR(100),
    product            VARCHAR(255),
    net_quantity       INT,
    gross_sales        DECIMAL(12,2),
    discounts          DECIMAL(12,2),
    returns            INT,
    net_sales          DECIMAL(12,2),
    shipping           DECIMAL(12,2),
    taxes              DECIMAL(12,2),
    total_sales        DECIMAL(12,2),
    product_clean      VARCHAR(255),
    product_type_clean VARCHAR(100),
    month              VARCHAR(7)
) CHARACTER SET utf8mb4;

-- CSV preparation (done in Excel, not SQL):
--   * Order ID and Sale ID must be exported as TEXT (=TEXT(A2,"0"), then paste
--     values). Excel writes CSVs using the DISPLAYED value, so plain numbers
--     came out as 2850000000000 (3 significant digits) and destroyed the IDs.
--   * Check the CSV in Notepad: the first row must start with
--     2854884835480,8725409595544,2020-11-11T01:39:33+03:00,TS1011
--   * Then: right-click raw_sales -> Table Data Import Wizard.


-- =====================================================================
-- 2. CHECKPOINT — RECONCILE THE LOAD AGAINST EXCEL
-- =====================================================================
SELECT COUNT(*)                 AS row_count,
       COUNT(DISTINCT sale_id)  AS distinct_sale_ids,
       COUNT(DISTINCT order_id) AS distinct_order_ids,
       SUM(total_sales)         AS total_revenue
FROM raw_sales;
-- Expected: 28755 | 28755 | 13257 | 82792157.40


-- Diagnosing a gap: compare row counts and revenue per month with Excel.
SELECT month, COUNT(*) AS rows_loaded, SUM(total_sales) AS revenue
FROM raw_sales
GROUP BY month
ORDER BY month;

-- Warnings from the last import, if any:
-- SHOW WARNINGS;


-- =====================================================================
-- 3. BUILD THE STAR SCHEMA
-- =====================================================================
-- Create parents first: sales points to both orders and products.
CREATE TABLE products (
    product_id    INT AUTO_INCREMENT PRIMARY KEY,
    product_name  VARCHAR(255) NOT NULL,
    product_type  VARCHAR(100) NOT NULL
);

CREATE TABLE orders (
    order_id       BIGINT PRIMARY KEY,
    order_code     VARCHAR(20)  NOT NULL,
    sales_channel  VARCHAR(30)  NOT NULL,
    order_date     DATETIME     NOT NULL
);

CREATE TABLE sales (
    sale_id           BIGINT PRIMARY KEY,
    order_id          BIGINT NOT NULL,
    product_id        INT NOT NULL,
    sale_date         DATETIME NOT NULL,
    transaction_type  VARCHAR(30),
    sale_type         VARCHAR(20),
    net_quantity      INT,
    gross_sales       DECIMAL(12,2),
    discounts         DECIMAL(12,2),
    returns           INT,
    net_sales         DECIMAL(12,2),
    shipping          DECIMAL(12,2),
    taxes             DECIMAL(12,2),
    total_sales       DECIMAL(12,2),
    FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Fill them from raw_sales, in this order.

-- 4a. One row per product. GROUP BY de-duplicates (like Remove Duplicates),
--     and MySQL's default text comparison ignores case, like Excel's.
INSERT INTO products (product_name, product_type)
SELECT product_clean, MIN(product_type_clean)
FROM raw_sales
GROUP BY product_clean;

-- 4b. One row per order. Each order has one code and one channel, so MIN()
--     cannot hide a conflict; for dates it takes the earliest line item.
INSERT INTO orders (order_id, order_code, sales_channel, order_date)
SELECT order_id,
       MIN(order_code),
       MIN(sales_channel),
       MIN(STR_TO_DATE(LEFT(sale_date, 19), '%Y-%m-%dT%H:%i:%s'))
FROM raw_sales
GROUP BY order_id;

-- 4c. The fact table: product names are swapped for product_ids.
--     LEFT(sale_date, 19) drops the "+03:00" before converting to a real date.
INSERT INTO sales
SELECT r.sale_id, r.order_id, p.product_id,
       STR_TO_DATE(LEFT(r.sale_date, 19), '%Y-%m-%dT%H:%i:%s'),
       r.transaction_type, r.sale_type, r.net_quantity,
       r.gross_sales, r.discounts, r.returns, r.net_sales,
       r.shipping, r.taxes, r.total_sales
FROM raw_sales r
JOIN products p ON p.product_name = r.product_clean;

-- Checkpoint
SELECT (SELECT COUNT(*) FROM products) AS products,   -- 1890 (1,889 + the
       (SELECT COUNT(*) FROM orders)   AS orders,     --  [Shipping/Fee Line]
       (SELECT COUNT(*) FROM sales)    AS sales,      --  placeholder)
       (SELECT SUM(total_sales) FROM sales) AS revenue;
-- Expected: 1890 | 13257 | 28755 | 82792157.40


-- =====================================================================
-- 4. QUERIES
-- =====================================================================

-- ---------------------------------------------------------------------
-- Query 1: dates converted properly
-- ---------------------------------------------------------------------
SELECT MIN(sale_date) AS first_sale, MAX(sale_date) AS last_sale
FROM sales;
-- Expected: 2020-11-11 ... 2023-10-31 (last sale 2023-10-31 18:26:21, so
-- October 2023 is a full month; November 2020 is a PARTIAL month).

-- ---------------------------------------------------------------------
-- Query 2: revenue by month (GROUP BY, one table)
-- ---------------------------------------------------------------------
SELECT DATE_FORMAT(sale_date, '%Y-%m') AS month,
       COUNT(*)                        AS line_items,
       SUM(total_sales)                AS revenue
FROM sales
GROUP BY month
ORDER BY month;
-- Expected: 36 rows; line_items sum to 28755; revenue sums to 82792157.40.

-- ---------------------------------------------------------------------
-- Query 3: revenue by category (first JOIN)
-- ---------------------------------------------------------------------
SELECT p.product_type,
       SUM(s.total_sales) AS revenue
FROM sales s
JOIN products p ON p.product_id = s.product_id
GROUP BY p.product_type
ORDER BY revenue DESC
LIMIT 6;
-- Expected top 6: Baby Formula 46,857,812.01 | Feeding And Weaning
-- 8,463,953.83 | Bathing & Skin Care 7,557,117.97 | Baby Diapers
-- 6,004,715.13 | Uncategorized 2,691,749.08 | Delivery Fee 1,826,262.05

-- Learn about: Foreign keys at work (this INSERT is EXPECTED to fail with error 1452,
-- because product_id 999999 does not exist):
-- INSERT INTO sales (sale_id, order_id, product_id, sale_date)
-- VALUES (1, 2854884835480, 999999, NOW());

-- ---------------------------------------------------------------------
-- Query 4: HAVING (filter AFTER grouping)
-- ---------------------------------------------------------------------
SELECT DATE_FORMAT(sale_date, '%Y-%m') AS month,
       SUM(total_sales) AS revenue
FROM sales
GROUP BY month
HAVING revenue > 3000000
ORDER BY month;
-- Expected: 11 months — 2022-11, then 2023-01 through 2023-10.
-- (2022-12 at about 2.78M falls back under the line.)

-- ---------------------------------------------------------------------
-- Query 5: three-table join — which channel sells which category
-- ---------------------------------------------------------------------
SELECT o.sales_channel,
       p.product_type,
       SUM(s.total_sales) AS revenue
FROM sales s
JOIN orders   o ON o.order_id   = s.order_id
JOIN products p ON p.product_id = s.product_id
GROUP BY o.sales_channel, p.product_type
ORDER BY o.sales_channel, revenue DESC;
-- Baby Formula leads both Online Store and Point of Sale.

-- ---------------------------------------------------------------------
-- Query 6: subquery — average ORDER value by channel
-- ---------------------------------------------------------------------
-- The inner query makes one row per order; the outer query averages them.
SELECT o.sales_channel,
       COUNT(*)                     AS orders,
       ROUND(AVG(t.order_total), 2) AS avg_order_value
FROM (
    SELECT order_id, SUM(total_sales) AS order_total
    FROM sales
    GROUP BY order_id
) t
JOIN orders o ON o.order_id = t.order_id
GROUP BY o.sales_channel;
-- Expected: Online Store 996 / 6200.42 | Point of Sale 12260 / 6247.20 |
--           Draft Orders 1 / 25839.99

-- ---------------------------------------------------------------------
-- Query 7: window function — running total
-- ---------------------------------------------------------------------
-- GROUP BY collapses rows; OVER (...) keeps every row and adds a calculation.
SELECT month, revenue,
       SUM(revenue) OVER (ORDER BY month) AS running_total
FROM (
    SELECT DATE_FORMAT(sale_date, '%Y-%m') AS month,
           SUM(total_sales) AS revenue
    FROM sales
    GROUP BY month
) m
ORDER BY month;
-- Expected: the last running_total is 82792157.40

-- ---------------------------------------------------------------------
-- Query 8: top 10 Uncategorized products by revenue
-- ---------------------------------------------------------------------
-- Tells you which of the 332 Uncategorized products to review first.
SELECT p.product_name,
       p.product_type,
       SUM(s.total_sales) AS revenue
FROM products p
JOIN sales s ON s.product_id = p.product_id
WHERE p.product_type = 'Uncategorized'
GROUP BY p.product_id, p.product_name, p.product_type
ORDER BY revenue DESC
LIMIT 10;
-- Expected #1: SMA PRO Growing Up Milk 800 g — 359,600.00
-- (Top 10 = ~32% of Uncategorized revenue; top 25 = ~48%.)

-- ---------------------------------------------------------------------
-- Query 9: share of each channel's revenue by category (PARTITION BY)
-- ---------------------------------------------------------------------
-- PARTITION BY restarts the window for each channel. Remove it (keep an
-- empty OVER ()) and the shares become % of ALL revenue instead.
SELECT o.sales_channel,
       p.product_type,
       SUM(s.total_sales) AS revenue,
       ROUND(100 * SUM(s.total_sales)
             / SUM(SUM(s.total_sales)) OVER (PARTITION BY o.sales_channel), 2) AS pct_of_channel
FROM sales s
JOIN orders   o ON o.order_id   = s.order_id
JOIN products p ON p.product_id = s.product_id
GROUP BY o.sales_channel, p.product_type
ORDER BY o.sales_channel, revenue DESC;
-- Expected: Baby Formula 40.75% (Online) vs 57.89% (Point of Sale);
-- Safety & Wellness 2.17% (Online) vs 0.75% (Point of Sale).

-- ---------------------------------------------------------------------
-- LEFT JOIN vs INNER JOIN test
-- ---------------------------------------------------------------------
INSERT INTO products (product_name, product_type)
VALUES ('TEST PRODUCT', 'Test');

-- INNER JOIN: returns no rows (no match, so the product disappears)
SELECT p.product_name, COUNT(s.sale_id) AS sales_count
FROM products p
JOIN sales s ON s.product_id = p.product_id
WHERE p.product_name = 'TEST PRODUCT'
GROUP BY p.product_id;

-- LEFT JOIN: one row, sales_count = 0
-- COUNT(s.sale_id) ignores NULLs, so it gives 0; COUNT(*) would give 1.
SELECT p.product_name, COUNT(s.sale_id) AS sales_count
FROM products p
LEFT JOIN sales s ON s.product_id = p.product_id
WHERE p.product_name = 'TEST PRODUCT'
GROUP BY p.product_id;

-- Clean up, then confirm the count is back to 1890:
DELETE FROM products WHERE product_name = 'TEST PRODUCT';
SELECT COUNT(*) FROM products;

-- ---------------------------------------------------------------------
-- Month-over-month growth: LAG()
-- ---------------------------------------------------------------------
-- LAG(revenue) = the revenue from the previous row (previous month).
-- The first month has no previous row, so its growth is NULL.
SELECT month,
       revenue,
       LAG(revenue) OVER (ORDER BY month) AS prev_revenue,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY month))
                 / LAG(revenue) OVER (ORDER BY month), 2) AS mom_growth_pct
FROM (
    SELECT DATE_FORMAT(sale_date, '%Y-%m') AS month,
           SUM(total_sales) AS revenue
    FROM sales
    GROUP BY month
) m
ORDER BY month;
-- Expected: 2020-12 +67.87 | 2021-04 -25.58 | 2022-09 +45.16 |
--           2022-12 -10.94 | 2023-07 -17.19 | 2023-10 -11.33
-- Caution: 2020-12's +67.87 is inflated because Nov 2020 is a partial month.

-- ---------------------------------------------------------------------
-- Year-over-year growth: the same query with LAG(revenue, 12)
-- ---------------------------------------------------------------------
-- LAG counts ROWS, not calendar months. It is correct here only because all
-- 36 months are present; one missing month would shift every comparison.
SELECT month,
       revenue,
       LAG(revenue, 12) OVER (ORDER BY month) AS same_month_last_year,
       ROUND(100 * (revenue - LAG(revenue, 12) OVER (ORDER BY month))
                 / LAG(revenue, 12) OVER (ORDER BY month), 2) AS yoy_growth_pct
FROM (
    SELECT DATE_FORMAT(sale_date, '%Y-%m') AS month,
           SUM(total_sales) AS revenue
    FROM sales
    GROUP BY month
) m
ORDER BY month;
-- Expected: first 12 months NULL | 2021-11 +70.26 (partial-month base) |
--           2022-11 +103.46 | 2023-01 +178.72 | 2023-10 +34.33
