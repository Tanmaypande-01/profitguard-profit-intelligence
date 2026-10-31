-- Start Schema 

USE profitguard;
-- Step 1. Relation Ships ( Star schema ) and indexes

ALTER TABLE fact_orders
  ADD FOREIGN KEY (customer_id) REFERENCES dim_customer(customer_id),
  ADD FOREIGN KEY (salesperson_id) REFERENCES dim_salesperson(salesperson_id),
  ADD FOREIGN KEY (location_id) REFERENCES dim_location(location_id);
ALTER TABLE fact_order_items
  ADD FOREIGN KEY (order_id) REFERENCES fact_orders(order_id),
  ADD FOREIGN KEY (product_id) REFERENCES dim_product(product_id);
ALTER TABLE fact_returns
  ADD FOREIGN KEY (order_item_id) REFERENCES fact_order_items(order_item_id);
CREATE INDEX idx_orders_date ON fact_orders(order_date);

-- -------------------------------------------------------------------------------------------------------------

-- Step 2. Cheack data 

SELECT COUNT(*) FROM stg_orders;            -- 11055 
SELECT COUNT(*) FROM fact_orders;           -- 11000 
SELECT 
    payment_status, COUNT(*)
FROM
    fact_orders
GROUP BY payment_status;

-- --------------------------------------------------------------------------------------------------------------------------------------

-- Step 3. Create New Table : stg_orders_raw 

CREATE TABLE stg_orders_raw (
    order_id VARCHAR(20),
    order_date VARCHAR(20),
    ship_date VARCHAR(20),
    delivery_date VARCHAR(20),
    customer_id VARCHAR(20),
    salesperson_id VARCHAR(20),
    location_id VARCHAR(20),
    channel VARCHAR(40),
    ship_mode VARCHAR(30),
    payment_method VARCHAR(40),
    payment_terms_days VARCHAR(10),
    due_date VARCHAR(20),
    paid_date VARCHAR(20),
    payment_status VARCHAR(30),
    shipping_cost VARCHAR(20),
    shipping_fee_collected VARCHAR(20)
);

-- --------------------------------------------------------------------------------------------------------------------------------------

-- Step 4. Chek Data 

SELECT 
    COUNT(*)
FROM
    stg_orders_raw;                              -- 11055 
    
SELECT 
    payment_status, COUNT(*)
FROM
    stg_orders_raw
GROUP BY 1;   -- Paid, Pending, Written Off

-- ---------------------------------------------------------------------------------------------------------------------------------------

-- Step 5.TRUNCATE Table : stg_orders 

TRUNCATE stg_orders;
INSERT INTO stg_orders
SELECT order_id,
 STR_TO_DATE(NULLIF(order_date,''),'%Y-%m-%d'), STR_TO_DATE(NULLIF(ship_date,''),'%Y-%m-%d'),
 STR_TO_DATE(NULLIF(delivery_date,''),'%Y-%m-%d'),
 customer_id, salesperson_id, location_id, channel, ship_mode, payment_method,
 CAST(NULLIF(payment_terms_days,'') AS SIGNED),
 STR_TO_DATE(NULLIF(due_date,''),'%Y-%m-%d'), STR_TO_DATE(NULLIF(paid_date,''),'%Y-%m-%d'),
 payment_status,
 CAST(NULLIF(shipping_cost,'') AS DECIMAL(12,2)), CAST(NULLIF(shipping_fee_collected,'') AS DECIMAL(12,2))
FROM stg_orders_raw;

SELECT 
    COUNT(*)
FROM
    stg_orders;   -- 11055

-- ----------------------------------------------------------------------------------------------------------------------------------------

-- Step 6.DROP Table : fact_orders 

DROP TABLE fact_orders;

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

ALTER TABLE fact_orders
  ADD FOREIGN KEY (customer_id) REFERENCES dim_customer(customer_id),
  ADD FOREIGN KEY (salesperson_id) REFERENCES dim_salesperson(salesperson_id),
  ADD FOREIGN KEY (location_id) REFERENCES dim_location(location_id);
CREATE INDEX idx_orders_date ON fact_orders(order_date);

-- ----------------------------------------------------------------------------------------------------------------------------------------

-- Step 7. Check Data 

SELECT COUNT(*) FROM fact_orders;                              -- 11000
SELECT payment_status, COUNT(*) FROM fact_orders GROUP BY 1;   -- Paid, Pending, Written Off 

-- ----------------------------------------------------------------------------------------------------------------------------------------

-- Step 8. ALTER TABLE: fact_order_items


ALTER TABLE fact_order_items
  ADD FOREIGN KEY (order_id) REFERENCES fact_orders(order_id),
  ADD FOREIGN KEY (product_id) REFERENCES dim_product(product_id);

ALTER TABLE fact_returns
  ADD FOREIGN KEY (order_item_id) REFERENCES fact_order_items(order_item_id);

-- ----------------------------------------------------------------------------------------------------------------------------------------

-- Step 9. Check All Data.

SELECT COUNT(*) FROM fact_order_items;                               -- 29007
SELECT COUNT(*) FROM fact_returns;                                   -- 1254
SELECT COUNT(*) FROM fact_orders WHERE ship_date_fixed=1;            -- 20
SELECT COUNT(*) FROM fact_orders WHERE payment_method='Unknown';     -- 88
SELECT COUNT(*) FROM fact_orders WHERE ship_mode='Unknown';          -- 55

SELECT ROUND(SUM(net_sales)/10000000,2) AS net_sales_crore,
       ROUND(SUM(line_profit)/SUM(net_sales)*100,1) AS margin_pct
FROM fact_order_items;                                               -- 39.52 & 16.8

-- ------------------------- -- ------------------------- -- --------------------------- -- ----------------------------- -- ---------------------------- -- ---------------------------- -- --------
