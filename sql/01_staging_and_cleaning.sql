-- Staging And Cleaning

-- Create data base profitguard
CREATE DATABASE profitguard;
USE profitguard;

-- 1. create table  stg_customers
CREATE TABLE stg_customers (
    customer_id VARCHAR(10),
    customer_name VARCHAR(100),
    segment VARCHAR(30),
    location_id VARCHAR(10),
    signup_date DATE,
    credit_terms_days INT,
    credit_limit INT,
    salesperson_id VARCHAR(10),
    email VARCHAR(120)
);

-- 2. create table stg_products
CREATE TABLE stg_products (
    product_id VARCHAR(10),
    product_name VARCHAR(100),
    category VARCHAR(40),
    sub_category VARCHAR(60),
    brand VARCHAR(30),
    supplier_id VARCHAR(10),
    list_price DECIMAL(12 , 2 ),
    standard_cost DECIMAL(12 , 2 ),
    weight_kg DECIMAL(8 , 2 ),
    launch_date DATE,
    is_active CHAR(1)
);

-- 3. create table stg_suppliers
CREATE TABLE stg_suppliers (
    supplier_id VARCHAR(10),
    supplier_name VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(30),
    lead_time_days INT,
    payment_terms_days INT,
    reliability_rating DECIMAL(2 , 1 )
);

-- 4. create table stg_locations
CREATE TABLE stg_locations (
    location_id VARCHAR(10),
    city VARCHAR(50),
    state VARCHAR(50),
    region VARCHAR(20),
    city_tier INT
);

-- 5. create table stg_salespersons
CREATE TABLE stg_salespersons (
    salesperson_id VARCHAR(10),
    salesperson_name VARCHAR(80),
    region VARCHAR(20),
    manager_name VARCHAR(80),
    hire_date DATE
);

-- 6. create table stg_orders
CREATE TABLE stg_orders (
    order_id VARCHAR(15),
    order_date DATE,
    ship_date DATE,
    delivery_date DATE,
    customer_id VARCHAR(10),
    salesperson_id VARCHAR(10),
    location_id VARCHAR(10),
    channel VARCHAR(30),
    ship_mode VARCHAR(20),
    payment_method VARCHAR(30),
    payment_terms_days INT,
    due_date DATE,
    paid_date DATE,
    payment_status VARCHAR(20),
    shipping_cost DECIMAL(12 , 2 ),
    shipping_fee_collected DECIMAL(12 , 2 )
);

-- 7. create table stg_order_items
CREATE TABLE stg_order_items (
    order_item_id VARCHAR(25),
    order_id VARCHAR(15),
    product_id VARCHAR(10),
    quantity INT,
    unit_price DECIMAL(12 , 2 ),
    unit_cost DECIMAL(12 , 2 ),
    discount_pct DECIMAL(5 , 2 ),
    discount_approval VARCHAR(20)
);

-- 8. create table stg_returns
CREATE TABLE stg_returns (
    return_id VARCHAR(10),
    order_id VARCHAR(15),
    order_item_id VARCHAR(25),
    product_id VARCHAR(10),
    return_date DATE,
    return_quantity INT,
    return_reason VARCHAR(40),
    refund_amount DECIMAL(12 , 2 ),
    restocked CHAR(1),
    return_shipping_cost DECIMAL(12 , 2 )
);

-- 9.create table stg_discount_policy
CREATE TABLE stg_discount_policy (
    category VARCHAR(40),
    standard_max_discount_pct INT,
    manager_approval_max_pct INT,
    effective_from DATE
);

-- 10.create table stg_sales_targets
CREATE TABLE stg_sales_targets (
    salesperson_id VARCHAR(10),
    year INT,
    month INT,
    target_sales BIGINT
);

-- 11.create tablestg_dim_date 
CREATE TABLE stg_dim_date (date_key INT,
 full_date DATE,
 year INT,
 quarter INT,
 month_num INT,
 month_name VARCHAR(15),
 month_short VARCHAR(5),
 `year_month` VARCHAR(7), 
 week_of_year INT,
 day_of_week_num INT,
 day_name VARCHAR(15),
 is_weekend CHAR(1),
 fiscal_year VARCHAR(10),
 fiscal_quarter INT,
 season_flag VARCHAR(20)
 );
 
 -- ------------------------------------------------------------------------------------------------------------------------------------------
 -- check all tables
 
SELECT 
    'customers', COUNT(*)
FROM
    stg_customers;

SELECT 
    'dim_date', COUNT(*)
FROM
    stg_dim_date;

SELECT 
    'discount_policy', COUNT(*)
FROM
    stg_dim_date;

SELECT 
    'locations', COUNT(*)
FROM
    stg_dim_date;

SELECT 
    'order_items', COUNT(*)
FROM
    stg_order_items;

SELECT 
    'orders', COUNT(*)
FROM
    stg_orders;

SELECT 
    'products', COUNT(*)
FROM
    stg_products;

SELECT 
    'returns', COUNT(*)
FROM
    stg_returns;

SELECT 
    'sales_targets', COUNT(*)
FROM
    stg_products;

SELECT 
    'Salespersons', COUNT(*)
FROM
    stg_products;

SELECT 
    'suppliers', COUNT(*)
FROM
    stg_products;

-- -------------------------------------------------------------------------------------------------------------

-- Step 1 Dimension table

CREATE TABLE dim_location AS SELECT * FROM
    stg_locations;
ALTER TABLE dim_location ADD PRIMARY KEY (location_id);

CREATE TABLE dim_salesperson AS SELECT * FROM
    stg_salespersons;
ALTER TABLE dim_salesperson ADD PRIMARY KEY (salesperson_id);

CREATE TABLE dim_supplier AS SELECT * FROM
    stg_suppliers;
ALTER TABLE dim_supplier ADD PRIMARY KEY (supplier_id);

CREATE TABLE dim_product AS SELECT * FROM
    stg_products;
ALTER TABLE dim_product ADD PRIMARY KEY (product_id);

CREATE TABLE dim_date AS SELECT * FROM
    stg_dim_date;
ALTER TABLE dim_date ADD PRIMARY KEY (date_key);

CREATE TABLE discount_policy AS SELECT * FROM
    stg_discount_policy;
ALTER TABLE discount_policy ADD PRIMARY KEY (category);

CREATE TABLE sales_targets AS SELECT * FROM
    stg_sales_targets;
ALTER TABLE sales_targets ADD PRIMARY KEY (salesperson_id, year, month);

-- -------------------------------------------------------------------------------------------------------------

-- Step 2 Customers: remove space , correct segment , convert blank email into NULL .

CREATE TABLE dim_customer AS SELECT customer_id,
    TRIM(customer_name) AS customer_name,
    CASE LOWER(TRIM(segment))
        WHEN 'consumer' THEN 'Consumer'
        WHEN 'small business' THEN 'Small Business'
        WHEN 'corporate' THEN 'Corporate'
        WHEN 'distributor' THEN 'Distributor'
    END AS segment,
    location_id,
    signup_date,
    credit_terms_days,
    credit_limit,
    salesperson_id,
    NULLIF(TRIM(email), '') AS email FROM
    stg_customers;
ALTER TABLE dim_customer ADD PRIMARY KEY (customer_id);

-- -------------------------------------------------------------------------------------------------------------

-- Step 3 Orders: Remove duplicates, correct a ship_date & fill blank values.

CREATE TABLE fact_orders AS SELECT DISTINCT order_id,
    order_date,
    CASE
        WHEN ship_date < order_date THEN order_date
        ELSE ship_date
    END AS ship_date,
    (ship_date < order_date) AS ship_date_fixed,
    delivery_date,
    customer_id,
    salesperson_id,
    location_id,
    channel,
    COALESCE(NULLIF(TRIM(ship_mode), ''), 'Unknown') AS ship_mode,
    COALESCE(NULLIF(TRIM(payment_method), ''),
            'Unknown') AS payment_method,
    payment_terms_days,
    due_date,
    paid_date,
    payment_status,
    shipping_cost,
    shipping_fee_collected FROM
    stg_orders;
ALTER TABLE fact_orders ADD PRIMARY KEY (order_id);

-- -------------------------------------------------------------------------------------------------------------

-- Step 4. Order items: Remove duplicate

CREATE TABLE fact_order_items AS SELECT DISTINCT order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    unit_cost,
    discount_pct,
    discount_approval FROM
    stg_order_items;
ALTER TABLE fact_order_items ADD PRIMARY KEY (order_item_id);

-- -------------------------------------------------------------------------------------------------------------

-- Step 5. Add Column : Sales,Cost,Profit 

ALTER TABLE fact_order_items
  ADD COLUMN gross_sales DECIMAL(14,2) GENERATED ALWAYS AS (quantity*unit_price) STORED,
  ADD COLUMN discount_amount DECIMAL(14,2) GENERATED ALWAYS AS (ROUND(quantity*unit_price*discount_pct/100,2)) STORED,
  ADD COLUMN net_sales DECIMAL(14,2) GENERATED ALWAYS AS (ROUND(quantity*unit_price*(1-discount_pct/100),2)) STORED,
  ADD COLUMN total_cost DECIMAL(14,2) GENERATED ALWAYS AS (ROUND(quantity*unit_cost,2)) STORED,
  ADD COLUMN line_profit DECIMAL(14,2) GENERATED ALWAYS AS (ROUND(quantity*unit_price*(1-discount_pct/100)-quantity*unit_cost,2)) STORED;

CREATE TABLE fact_returns AS SELECT * FROM
    stg_returns;
ALTER TABLE fact_returns ADD PRIMARY KEY (return_id);
 
 
-- -------------------------------------------------------------------------------------------------------------

-- Step 6. Check Data 

SELECT 
    COUNT(*)
FROM
    fact_orders;                  -- 11000
SELECT 
    COUNT(*)
FROM
    fact_order_items;             -- 29007
SELECT 
    COUNT(*)
FROM
    fact_orders
WHERE
    ship_date_fixed = 1;            -- 20
SELECT 
    COUNT(*)
FROM
    fact_orders
WHERE
    payment_method = 'Unknown';     -- 88
SELECT 
    COUNT(*)
FROM
    fact_orders
WHERE
    ship_mode = 'Unknown';          -- 55
SELECT 
    segment, COUNT(*)
FROM
    dim_customer
GROUP BY segment;                  -- 4 lime

SELECT 
    ROUND(SUM(net_sales) / 10000000, 2) AS net_sales_crore,
    ROUND(SUM(line_profit) / SUM(net_sales) * 100,
            1) AS margin_pct
FROM
    fact_order_items;                      
    
-- -------------------------------------------------------------------------------------------------------------

-- Step 7. Orphan Checking

SELECT 
    COUNT(*)
FROM
    fact_order_items i
        LEFT JOIN
    fact_orders o ON o.order_id = i.order_id
WHERE
    o.order_id IS NULL;
SELECT 
    COUNT(*)
FROM
    fact_order_items i
        LEFT JOIN
    dim_product p ON p.product_id = i.product_id
WHERE
    p.product_id IS NULL;
SELECT 
    COUNT(*)
FROM
    fact_orders o
        LEFT JOIN
    dim_customer c ON c.customer_id = o.customer_id
WHERE
    c.customer_id IS NULL;

-- ------------------------- -- ------------------------- -- --------------------------- -- ----------------------------- -- ---------------------------- -- ---------------------------- -- --------
