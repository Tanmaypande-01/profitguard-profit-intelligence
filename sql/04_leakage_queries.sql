-- Leakage Queries

USE profitguard;
-- Step 1. Leakage Detection Queries 

SELECT 
    ROUND((SELECT 
                    SUM(net_sales)
                FROM
                    fact_order_items) / 100000,
            1) AS net_sales_lakh,
    ROUND((SELECT 
                    SUM(line_profit)
                FROM
                    fact_order_items) / 100000,
            1) AS gross_profit_lakh,
    ROUND((SELECT 
                    SUM(excess_discount)
                FROM
                    vw_line_leakage) / 100000,
            1) AS discount_leak_lakh,
    ROUND((SELECT 
                    SUM(return_loss)
                FROM
                    vw_return_loss) / 100000,
            1) AS return_leak_lakh,
    ROUND((SELECT 
                    SUM(shipping_loss)
                FROM
                    vw_order_leakage) / 100000,
            1) AS shipping_leak_lakh,
    ROUND((SELECT 
                    SUM(bad_debt_loss)
                FROM
                    vw_order_leakage) / 100000,
            1) AS bad_debt_lakh;
       
-- ---------------------------------------------------------------------------------------------------------------

-- Step 2. Discount Leakage :  At what discount does the loss start

SELECT 
    discount_band,
    COUNT(*) AS liness,
    ROUND(SUM(line_profit) / SUM(net_sales) * 100,
            1) AS margin_pct
FROM
    vw_line_leakage
GROUP BY discount_band
ORDER BY discount_band;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 3. Which salesperson leaks the most ( excessive discount )

SELECT 
    s.salesperson_name,
    s.region,
    ROUND(AVG(v.discount_pct), 1) AS avg_disc,
    ROUND(SUM(v.excess_discount) / 100000, 2) AS excess_lakh,
    ROUND(SUM(v.line_profit) / SUM(v.net_sales) * 100,
            1) AS margin_pct
FROM
    vw_line_leakage v
        JOIN
    dim_salesperson s ON s.salesperson_id = v.salesperson_id
GROUP BY s.salesperson_id , s.salesperson_name , s.region
ORDER BY excess_lakh DESC
LIMIT 10;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 4. Discount without approval ( control failure) 

SELECT 
    discount_approval,
    COUNT(*) AS liness,
    ROUND(SUM(excess_discount) / 100000, 2) AS excess_lakh
FROM
    vw_line_leakage
WHERE
    excess_discount > 0
GROUP BY discount_approval;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 5. Products in loss

SELECT 
    product_id,
    product_name,
    category,
    SUM(quantity) AS units,
    ROUND(SUM(net_sales) / 100000, 2) AS sales_lakh,
    ROUND(SUM(line_profit) / 100000, 2) AS profit_lakh,
    ROUND(SUM(line_profit) / SUM(net_sales) * 100,
            1) AS margin_pct
FROM
    vw_line_leakage
GROUP BY product_id , product_name , category
HAVING SUM(line_profit) < 0
    OR SUM(line_profit) / SUM(net_sales) < 0.05
ORDER BY profit_lakh;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 6. Returns


SELECT 
    return_reason,
    COUNT(*) AS returns,
    ROUND(SUM(return_loss) / 100000, 2) AS loss_lakh
FROM
    vw_return_loss
GROUP BY return_reason
ORDER BY loss_lakh DESC;

WITH sold AS (SELECT product_id, SUM(quantity) AS sold_qty FROM fact_order_items GROUP BY product_id),
     ret  AS (SELECT product_id, SUM(return_quantity) AS ret_qty, SUM(return_loss) AS loss FROM vw_return_loss GROUP BY product_id)
SELECT p.product_name, p.category, s.sold_qty, r.ret_qty,
       ROUND(r.ret_qty/s.sold_qty*100,1) AS return_rate_pct, ROUND(r.loss/100000,2) AS loss_lakh
FROM sold s JOIN ret r ON r.product_id = s.product_id JOIN dim_product p ON p.product_id = s.product_id
ORDER BY return_rate_pct DESC LIMIT 10;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 7. Shipping leakage

SELECT 
    ship_mode,
    COUNT(*) AS orders,
    ROUND(SUM(shipping_loss) / 100000, 2) AS ship_loss_lakh,
    SUM(order_profit < shipping_loss) AS orders_where_ship_exceeds_profit
FROM
    vw_order_leakage
GROUP BY ship_mode
ORDER BY ship_loss_lakh DESC;

SELECT 
    l.region,
    ROUND(SUM(v.shipping_loss) / 100000, 2) AS ship_loss_lakh,
    ROUND(SUM(v.shipping_loss) / SUM(v.order_sales) * 100,
            2) AS loss_pct_of_sales
FROM
    vw_order_leakage v
        JOIN
    dim_location l ON l.location_id = v.location_id
GROUP BY l.region
ORDER BY loss_pct_of_sales DESC;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 8. Bad debt and late paying customer

SELECT 
    c.customer_name,
    c.segment,
    COUNT(*) AS written_off_orders,
    ROUND(SUM(v.bad_debt_loss) / 100000, 2) AS bad_debt_lakh
FROM
    vw_order_leakage v
        JOIN
    dim_customer c ON c.customer_id = v.customer_id
WHERE
    v.payment_status = 'Written Off'
GROUP BY c.customer_id , c.customer_name , c.segment
ORDER BY bad_debt_lakh DESC
LIMIT 10;

SELECT 
    c.customer_name,
    COUNT(*) AS paid_orders,
    ROUND(AVG(DATEDIFF(o.paid_date, o.due_date)),
            1) AS avg_delay_days
FROM
    fact_orders o
        JOIN
    dim_customer c ON c.customer_id = o.customer_id
WHERE
    o.paid_date IS NOT NULL
        AND o.payment_terms_days > 0
GROUP BY c.customer_id , c.customer_name
HAVING COUNT(*) >= 5
ORDER BY avg_delay_days DESC
LIMIT 10;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 9. Price Inconsistency ( Selling the same product at different price )

CREATE OR REPLACE VIEW vw_price_leakage AS
SELECT t.*, CASE WHEN unit_price < avg_price*0.97
                 THEN ROUND((avg_price-unit_price)*quantity,2) ELSE 0 END AS underpricing_loss
FROM (SELECT order_item_id, product_id, product_name, fiscal_year, quantity, unit_price,
             AVG(unit_price) OVER (PARTITION BY product_id, fiscal_year) AS avg_price
      FROM vw_line_leakage) t;

SELECT 
    product_name,
    fiscal_year,
    ROUND(MIN(unit_price)) AS min_price,
    ROUND(MAX(unit_price)) AS max_price,
    ROUND((MAX(unit_price) - MIN(unit_price)) / AVG(unit_price) * 100,
            1) AS spread_pct,
    ROUND(SUM(underpricing_loss) / 100000, 2) AS underpriced_lakh
FROM
    vw_price_leakage
GROUP BY product_id , product_name , fiscal_year
ORDER BY spread_pct DESC
LIMIT 10;

-- -------------------------------------------------------------------------------------------------------------

-- Step 10. Unusual behavior using Z-score 

SELECT * FROM (
  SELECT order_item_id, product_name, category, discount_pct, net_sales, line_profit,
         ROUND((line_profit/net_sales*100 - AVG(line_profit/net_sales*100) OVER (PARTITION BY category))
               / NULLIF(STDDEV_POP(line_profit/net_sales*100) OVER (PARTITION BY category),0), 2) AS z_margin
  FROM vw_line_leakage WHERE net_sales > 0) t
WHERE ABS(z_margin) > 3 ORDER BY z_margin LIMIT 50;

-- -------------------------------------------------------------------------------------------------------------

-- Step 11. Large but low-profit customers and churn

SELECT 
    c.customer_name,
    c.segment,
    r.rfm_segment,
    r.churn_status,
    ROUND(r.monetary / 100000, 2) AS sales_lakh,
    ROUND(r.profit / 100000, 2) AS profit_lakh,
    ROUND(r.profit / r.monetary * 100, 1) AS margin_pct
FROM
    vw_customer_rfm r
        JOIN
    dim_customer c ON c.customer_id = r.customer_id
WHERE
    r.m_score = 4
ORDER BY margin_pct
LIMIT 15;

SELECT 
    rfm_segment,
    churn_status,
    COUNT(*) AS customers,
    ROUND(SUM(monetary) / 100000, 1) AS sales_lakh
FROM
    vw_customer_rfm
GROUP BY rfm_segment , churn_status
ORDER BY rfm_segment;

-- -------------------------------------------------------------------------------------------------------------

-- Step 12. What-if : How much will you save if you set a discount limit

SELECT 
    c.cap AS discount_cap_pct,
    ROUND(SUM(CASE
                WHEN v.discount_pct > c.cap THEN v.quantity * v.unit_price * (v.discount_pct - c.cap) / 100
                ELSE 0
            END) / 100000,
            1) AS saving_lakh_3yrs
FROM
    vw_line_leakage v
        CROSS JOIN
    (SELECT 10 AS cap UNION SELECT 15 UNION SELECT 20 UNION SELECT 25) c
GROUP BY c.cap
ORDER BY c.cap;

-- ------------------------- -- ------------------------- -- --------------------------- -- ----------------------------- -- ---------------------------- -- ---------------------------- -- --------
