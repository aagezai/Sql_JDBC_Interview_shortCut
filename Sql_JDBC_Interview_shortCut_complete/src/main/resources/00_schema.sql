-- 00_schema.sql
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(150) UNIQUE,
  city VARCHAR(80),
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE categories (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(80) NOT NULL
);

CREATE TABLE products (
  id INT PRIMARY KEY AUTO_INCREMENT,
  category_id INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  stock INT NOT NULL DEFAULT 0,
  attrs JSON NULL,
  FOREIGN KEY (category_id) REFERENCES categories(id)
);

CREATE TABLE orders (
  id INT PRIMARY KEY AUTO_INCREMENT,
  customer_id INT NOT NULL,
  order_date DATE NOT NULL,
  status ENUM('NEW','PAID','CANCELLED') NOT NULL DEFAULT 'NEW',
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);

CREATE TABLE order_items (
  id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL,
  product_id INT NOT NULL,
  qty INT NOT NULL,
  unit_price DECIMAL(10,2) NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
);

CREATE TABLE payments (
  id INT PRIMARY KEY AUTO_INCREMENT,
  order_id INT NOT NULL,
  paid_at DATETIME NOT NULL,
  method ENUM('CARD','ACH','CASH') NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(id)
);

-- seed
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
-- 01_basics.sql
-- Select columns
SELECT id, name, city FROM customers;

-- Filtering
SELECT * FROM products WHERE price >= 500;

-- Multiple conditions
SELECT * FROM customers WHERE city='Dallas' AND email LIKE '%@ex.com';

-- Sorting + limiting
SELECT name, price FROM products ORDER BY price DESC LIMIT 2;

-- Aliases
SELECT p.name AS product, p.price AS usd FROM products p;
-- 02_aggregates.sql
-- Per-city customer counts
SELECT city, COUNT(*) AS customers
FROM customers
GROUP BY city
ORDER BY customers DESC;

-- Revenue by paid orders (from payments table)
SELECT DATE(paid_at) AS day, SUM(amount) AS revenue
FROM payments
GROUP BY DATE(paid_at)
ORDER BY day;

-- Avg price per category (join + group)
SELECT c.name AS category, AVG(p.price) AS avg_price
FROM categories c
JOIN products p ON p.category_id = c.id
GROUP BY c.name
HAVING AVG(p.price) > 200;  -- HAVING filters AFTER aggregation
-- 03_joins.sql
-- Orders with customer name (INNER)
SELECT o.id, c.name, o.status, o.order_date
FROM orders o
JOIN customers c ON c.id = o.customer_id;

-- Customers and their last order (LEFT with aggregate)
SELECT c.id, c.name, MAX(o.order_date) AS last_order
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
GROUP BY c.id, c.name;

-- RIGHT join example: categories and products (which categories have products?)
SELECT c.name AS category, p.name AS product
FROM products p
RIGHT JOIN categories c ON p.category_id = c.id
ORDER BY c.name;

-- FULL OUTER JOIN (MySQL workaround with UNION)
-- All customers and all orders (even if no match)
SELECT c.id AS customer_id, o.id AS order_id, c.name
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
UNION
SELECT c.id, o.id, c.name
FROM customers c
RIGHT JOIN orders o ON o.customer_id = c.id;
-- 04_subqueries.sql
-- Customers who placed any 'PAID' order
SELECT * FROM customers
WHERE id IN (
  SELECT customer_id FROM orders WHERE status='PAID'
);

-- Same with EXISTS (often faster)
SELECT c.*
FROM customers c
WHERE EXISTS (
  SELECT 1 FROM orders o
  WHERE o.customer_id = c.id AND o.status='PAID'
);

-- Scalar subquery: product above overall avg price
SELECT name, price
FROM products
WHERE price > (SELECT AVG(price) FROM products);
-- 05_set_ops.sql
-- All Dallas OR Seattle entities: customers and (fictional) vendors table substitute via products
SELECT name, city, 'CUSTOMER' AS kind FROM customers WHERE city IN ('Dallas','Seattle')
UNION ALL
SELECT name, NULL AS city, 'PRODUCT' AS kind FROM products WHERE price > 1000;
-- 06_window.sql
-- Rank customers by lifetime spend (compute from order_items)
WITH spend AS (
  SELECT c.id, c.name, COALESCE(SUM(oi.qty * oi.unit_price),0) AS total_spend
  FROM customers c
  LEFT JOIN orders o  ON o.customer_id = c.id
  LEFT JOIN order_items oi ON oi.order_id = o.id
  GROUP BY c.id, c.name
)
SELECT
  name,
  total_spend,
  RANK() OVER (ORDER BY total_spend DESC) AS spend_rank,
  ROW_NUMBER() OVER (ORDER BY total_spend DESC) AS rownum
FROM spend;

-- Running total of payments by date
SELECT
  DATE(paid_at) AS day,
  SUM(amount) AS daily_rev,
  SUM(SUM(amount)) OVER (ORDER BY DATE(paid_at)) AS running_rev
FROM payments
GROUP BY DATE(paid_at)
ORDER BY day;
-- 07_cte.sql
-- Non-recursive: top priced product per category
WITH ranked AS (
  SELECT
    p.*,
    ROW_NUMBER() OVER (PARTITION BY p.category_id ORDER BY p.price DESC) AS rn
  FROM products p
)
SELECT id, name, price, category_id
FROM ranked
WHERE rn = 1;

-- Recursive: simple numbers 1..10
WITH RECURSIVE nums AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n+1 FROM nums WHERE n < 10
)
SELECT * FROM nums;
-- 08_case_pivot.sql
-- Label products by price band
SELECT
  name,
  price,
  CASE
    WHEN price >= 1000 THEN 'HIGH'
    WHEN price >= 200  THEN 'MID'
    ELSE 'LOW'
  END AS price_band
FROM products;

-- Pivot-style: daily paid amounts by method (columns)
SELECT
  DATE(paid_at) AS day,
  SUM(CASE WHEN method='CARD' THEN amount ELSE 0 END) AS card_amt,
  SUM(CASE WHEN method='ACH'  THEN amount ELSE 0 END) AS ach_amt,
  SUM(CASE WHEN method='CASH' THEN amount ELSE 0 END) AS cash_amt
FROM payments
GROUP BY DATE(paid_at)
ORDER BY day;
-- 09_funcs.sql
-- Last 14 days orders
SELECT * FROM orders
WHERE order_date >= CURDATE() - INTERVAL 14 DAY;

-- Format names & email domain
SELECT
  UPPER(name) AS NAME_UP,
  SUBSTRING_INDEX(email,'@',-1) AS domain
FROM customers;

-- Round and math
SELECT name, price, ROUND(price * 1.0825, 2) AS price_with_tax
FROM products;
-- 10_json.sql
-- Extract attributes
SELECT
  name,
  JSON_EXTRACT(attrs,'$.brand') AS brand,
  JSON_UNQUOTE(JSON_EXTRACT(attrs,'$.color')) AS color
FROM products;

-- Filter by JSON key existence/value
SELECT *
FROM products
WHERE JSON_EXTRACT(attrs,'$.ram_gb') >= 16;
-- 11_dml_tx.sql
START TRANSACTION;

-- Insert a new order and items
INSERT INTO orders(customer_id,order_date,status) VALUES (4, CURDATE(), 'NEW');
SET @oid = LAST_INSERT_ID();

INSERT INTO order_items(order_id,product_id,qty,unit_price)
VALUES (@oid, 3, 1, 199);

-- Update stock atomically (check enough stock)
UPDATE products
SET stock = stock - 1
WHERE id = 3 AND stock >= 1;

-- Commit or rollback based on stock
SELECT stock INTO @s FROM products WHERE id = 3;
IF @s >= 0 THEN
  COMMIT;
ELSE
  ROLLBACK;
END IF;
-- 12_perf.sql
-- Create helpful indexes
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX idx_products_category_price ON products(category_id, price);

-- See query plan
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
-- 14_advanced.sql
-- Top-1 product per category (another pattern)
SELECT p.*
FROM products p
JOIN (
  SELECT category_id, MAX(price) AS max_price
  FROM products
  GROUP BY category_id
) mx ON mx.category_id = p.category_id AND mx.max_price = p.price;

-- Gaps & islands (payments by consecutive days)
WITH daily AS (
  SELECT DATE(paid_at) AS d
  FROM payments
  GROUP BY DATE(paid_at)
),
grp AS (
  SELECT
    d,
    DENSE_RANK() OVER (ORDER BY d) -
    DENSE_RANK() OVER (ORDER BY DATE_SUB(d, INTERVAL ROW_NUMBER() OVER (ORDER BY d) DAY)) AS island_id
  FROM (
    SELECT d, ROW_NUMBER() OVER (ORDER BY d) AS rn
    FROM daily
  ) t
)
SELECT MIN(d) AS start_day, MAX(d) AS end_day, COUNT(*) AS days
FROM grp
GROUP BY island_id
ORDER BY start_day;







