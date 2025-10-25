-- === ALL-IN-ONE MySQL 5.7+/8.x SAFE SCRIPT ===
SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- Clean rebuild
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS customers;
SET FOREIGN_KEY_CHECKS = 1;

-- ======================
-- SCHEMA
-- ======================
CREATE TABLE customers (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(150) UNIQUE,
  city VARCHAR(80),
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE categories (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(80) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE products (
  id INT PRIMARY KEY AUTO_INCREMENT,
  category_id INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  stock INT NOT NULL DEFAULT 0,
  attrs JSON NULL,
  CONSTRAINT fk_products_category
    FOREIGN KEY (category_id) REFERENCES categories(id)
) ENGINE=InnoDB;

CREATE TABLE orders (
  id INT PRIMARY KEY AUTO_INCREMENT,
  customer_id INT NOT NULL,
  order_date DATE NOT NULL,
  status ENUM('NEW','PAID','CANCELLED') NOT NULL DEFAULT 'NEW',
  CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB;

CREATE TABLE order_items (
  id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL,
  product_id INT NOT NULL,
  qty INT NOT NULL,
  unit_price DECIMAL(10,2) NOT NULL,
  CONSTRAINT fk_order_items_order
    FOREIGN KEY (order_id) REFERENCES orders(id),
  CONSTRAINT fk_order_items_product
    FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB;

CREATE TABLE payments (
  id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL,
  paid_at DATETIME NOT NULL,
  method ENUM('CARD','ACH','CASH') NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  CONSTRAINT fk_payments_order
    FOREIGN KEY (order_id) REFERENCES orders(id)
) ENGINE=InnoDB;

-- ======================
-- SEED DATA
-- ======================
INSERT INTO customers(name,email,city) VALUES
('Alice','alice@ex.com','Dallas'),
('Bob','bob@ex.com','Seattle'),
('Caro','caro@ex.com','Miami'),
('Dani','dani@ex.com','Dallas');

INSERT INTO categories(name) VALUES ('Electronics'),('Home'),('Books');

INSERT INTO products(category_id,name,price,stock,attrs) VALUES
(1,'Phone',699,10,'{"brand":"Acme","color":"black"}'),
(1,'Laptop',1299,5,'{"brand":"Acme","ram_gb":16}'),
(2,'Vacuum',199,20,'{"brand":"CleanCo"}'),
(3,'SQL 101',39,100,'{"format":"paperback"}');

INSERT INTO orders(customer_id,order_date,status) VALUES
(1,'2025-10-01','PAID'),
(1,'2025-10-12','PAID'),
(2,'2025-10-14','NEW'),
(3,'2025-10-20','CANCELLED');

INSERT INTO order_items(order_id,product_id,qty,unit_price) VALUES
(1,1,1,699),(1,4,1,39),
(2,2,1,1299),
(3,3,2,199),
(4,4,1,39);

INSERT INTO payments(order_id,paid_at,method,amount) VALUES
(1,'2025-10-01 10:05','CARD',738.00),
(2,'2025-10-12 09:30','ACH',1299.00);

-- ======================
-- BASICS
-- ======================
-- 01_basics.sql
SELECT id, name, city FROM customers;
SELECT * FROM products WHERE price >= 500;
SELECT * FROM customers WHERE city='Dallas' AND email LIKE '%@ex.com';
SELECT name, price FROM products ORDER BY price DESC LIMIT 2;
SELECT p.name AS product, p.price AS usd FROM products p;

-- 02_aggregates.sql
SELECT city, COUNT(*) AS customers
FROM customers
GROUP BY city
ORDER BY customers DESC;

SELECT DATE(paid_at) AS day, SUM(amount) AS revenue
FROM payments
GROUP BY DATE(paid_at)
ORDER BY day;

SELECT c.name AS category, AVG(p.price) AS avg_price
FROM categories c
JOIN products p ON p.category_id = c.id
GROUP BY c.name
HAVING AVG(p.price) > 200;

-- 03_joins.sql
SELECT o.id, c.name, o.status, o.order_date
FROM orders o
JOIN customers c ON c.id = o.customer_id;

SELECT c.id, c.name, MAX(o.order_date) AS last_order
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
GROUP BY c.id, c.name;

SELECT c.name AS category, p.name AS product
FROM products p
RIGHT JOIN categories c ON p.category_id = c.id
ORDER BY c.name;

-- FULL OUTER JOIN workaround (UNION of LEFT + RIGHT)
SELECT c.id AS customer_id, o.id AS order_id, c.name
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
UNION
SELECT c.id, o.id, c.name
FROM customers c
RIGHT JOIN orders o ON o.customer_id = c.id;

-- ======================
-- SUBQUERIES / SET OPS
-- ======================
-- 04_subqueries.sql
SELECT * FROM customers
WHERE id IN (SELECT customer_id FROM orders WHERE status='PAID');

SELECT c.*
FROM customers c
WHERE EXISTS (
  SELECT 1 FROM orders o
  WHERE o.customer_id = c.id AND o.status='PAID'
);

SELECT name, price
FROM products
WHERE price > (SELECT AVG(price) FROM products);

-- 05_set_ops.sql
SELECT name, city, 'CUSTOMER' AS kind FROM customers WHERE city IN ('Dallas','Seattle')
UNION ALL
SELECT name, NULL AS city, 'PRODUCT' AS kind FROM products WHERE price > 1000;

-- ======================
-- WINDOW ANALOGS (no CTE/window funcs)
-- ======================
-- 06_window.sql replacements

-- A) Lifetime spend per customer with rank & rownum via variables
DROP TEMPORARY TABLE IF EXISTS tmp_spend;
CREATE TEMPORARY TABLE tmp_spend AS
SELECT c.id, c.name, COALESCE(SUM(oi.qty * oi.unit_price),0) AS total_spend
FROM customers c
LEFT JOIN orders o  ON o.customer_id = c.id
LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY c.id, c.name;

SET @r := 0, @prev := NULL, @rownum := 0;
SELECT
  name,
  total_spend,
  (@r := IF(@prev = total_spend, @r, @r + 1)) AS spend_rank,
  (@rownum := @rownum + 1) AS rownum,
  (@prev := total_spend) AS _
FROM tmp_spend
ORDER BY total_spend DESC;

-- B) Running total of payments by date
DROP TEMPORARY TABLE IF EXISTS tmp_daily_rev;
CREATE TEMPORARY TABLE tmp_daily_rev AS
SELECT DATE(paid_at) AS day, SUM(amount) AS daily_rev
FROM payments
GROUP BY DATE(paid_at)
ORDER BY day;

SET @run := 0;
SELECT
  day,
  daily_rev,
  (@run := @run + daily_rev) AS running_rev
FROM tmp_daily_rev
ORDER BY day;

-- ======================
-- “CTE” ANALOGS (no WITH)
-- ======================
-- 07_cte.sql replacements
-- Top priced product per category
SELECT p.id, p.name, p.price, p.category_id
FROM products p
JOIN (
  SELECT category_id, MAX(price) AS max_price
  FROM products
  GROUP BY category_id
) mx ON mx.category_id = p.category_id AND mx.max_price = p.price;

-- Numbers 1..10 (no recursion)
SELECT n FROM (
  SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
  UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
) AS t;

-- ======================
-- CASE / PIVOT
-- ======================
-- 08_case_pivot.sql
SELECT
  name,
  price,
  CASE
    WHEN price >= 1000 THEN 'HIGH'
    WHEN price >= 200  THEN 'MID'
    ELSE 'LOW'
  END AS price_band
FROM products;

SELECT
  DATE(paid_at) AS day,
  SUM(CASE WHEN method='CARD' THEN amount ELSE 0 END) AS card_amt,
  SUM(CASE WHEN method='ACH'  THEN amount ELSE 0 END) AS ach_amt,
  SUM(CASE WHEN method='CASH' THEN amount ELSE 0 END) AS cash_amt
FROM payments
GROUP BY DATE(paid_at)
ORDER BY day;

-- ======================
-- FUNCS / JSON
-- ======================
-- 09_funcs.sql
SELECT * FROM orders
WHERE order_date >= CURDATE() - INTERVAL 14 DAY;

SELECT
  UPPER(name) AS NAME_UP,
  SUBSTRING_INDEX(email,'@',-1) AS domain
FROM customers;

SELECT name, price, ROUND(price * 1.0825, 2) AS price_with_tax
FROM products;

-- 10_json.sql  (JSON needs MySQL 5.7.8+ / any 8.x)
SELECT
  name,
  JSON_EXTRACT(attrs,'$.brand') AS brand,
  JSON_UNQUOTE(JSON_EXTRACT(attrs,'$.color')) AS color
FROM products;

SELECT *
FROM products
WHERE JSON_EXTRACT(attrs,'$.ram_gb') >= 16;

-- ======================
-- DML / TRANSACTION: use a stored procedure (valid place for IF/THEN)
-- ======================
-- 11_dml_tx.sql (fixed)
DELIMITER $$

DROP PROCEDURE IF EXISTS process_order $$
CREATE PROCEDURE process_order()
BEGIN
  DECLARE s INT DEFAULT 0;

  START TRANSACTION;

  -- Insert a new order for customer 4
  INSERT INTO orders(customer_id,order_date,status) VALUES (4, CURDATE(), 'NEW');
  SET @oid := LAST_INSERT_ID();

  -- Insert an item (product 3, qty 1, price 199)
  INSERT INTO order_items(order_id,product_id,qty,unit_price)
  VALUES (@oid, 3, 1, 199);

  -- Decrement stock only if enough inventory
  UPDATE products
  SET stock = stock - 1
  WHERE id = 3 AND stock >= 1;

  -- Check stock and commit/rollback
  SELECT stock INTO s FROM products WHERE id = 3;

  IF s >= 0 THEN
    COMMIT;
  ELSE
    ROLLBACK;
  END IF;
END $$
DELIMITER ;

-- Example execution (optional):
CALL process_order();

-- ======================
-- PERF / VIEWS / ADVANCED (no CTE/window)
-- ======================
-- 12_perf.sql
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX idx_products_category_price ON products(category_id, price);

EXPLAIN
SELECT o.id, o.order_date
FROM orders o
WHERE o.customer_id = 1
ORDER BY o.order_date DESC
LIMIT 5;

-- 13_views.sql
CREATE OR REPLACE VIEW v_customer_spend AS
SELECT c.id AS customer_id, c.name,
       COALESCE(SUM(oi.qty * oi.unit_price),0) AS lifetime_spend
FROM customers c
LEFT JOIN orders o  ON o.customer_id = c.id
LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY c.id, c.name;

SELECT * FROM v_customer_spend ORDER BY lifetime_spend DESC;

-- 14_advanced.sql replacement (gaps & islands without window/CTE)
DROP TEMPORARY TABLE IF EXISTS tmp_daily;
CREATE TEMPORARY TABLE tmp_daily AS
SELECT DISTINCT DATE(paid_at) AS d
FROM payments
ORDER BY d;

SET @rn := 0;
DROP TEMPORARY TABLE IF EXISTS tmp_rn;
CREATE TEMPORARY TABLE tmp_rn AS
SELECT d, (@rn := @rn + 1) AS rn
FROM tmp_daily
ORDER BY d;

SELECT MIN(d) AS start_day, MAX(d) AS end_day, COUNT(*) AS days
FROM (
  SELECT d, DATE_SUB(d, INTERVAL rn DAY) AS anchor
  FROM tmp_rn
) x
GROUP BY anchor
ORDER BY start_day;
