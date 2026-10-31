-- Views

USE profitguard;
-- Step 1. Line : level view 

CREATE OR REPLACE VIEW vw_line_leakage AS
    SELECT 
        i.order_item_id,
        i.order_id,
        o.order_date,
        d.fiscal_year,
        d.year_month,
        o.customer_id,
        o.salesperson_id,
        o.location_id,
        o.channel,
        i.product_id,
        p.product_name,
        p.category,
        i.quantity,
        i.unit_price,
        i.unit_cost,
        i.discount_pct,
        FLOOR(i.discount_pct / 5) * 5 AS discount_band,
        i.gross_sales,
        i.net_sales,
        i.total_cost,
        i.line_profit,
        CASE
            WHEN i.line_profit < 0 THEN 'Loss'
            ELSE 'Profit'
        END AS profit_flag,
        dp.standard_max_discount_pct AS policy_max_pct,
        i.discount_approval,
        CASE
            WHEN
                i.discount_pct > dp.standard_max_discount_pct
            THEN
                ROUND(i.quantity * i.unit_price * (i.discount_pct - dp.standard_max_discount_pct) / 100,
                        2)
            ELSE 0
        END AS excess_discount
    FROM
        fact_order_items i
            JOIN
        fact_orders o ON o.order_id = i.order_id
            JOIN
        dim_product p ON p.product_id = i.product_id
            JOIN
        discount_policy dp ON dp.category = p.category
            JOIN
        dim_date d ON d.full_date = o.order_date;
        
-- ---------------------------------------------------------------------------------------------------------------

-- Step 2. View : Order Returns loss : Refund + Unsold goods + return shipping costs

CREATE OR REPLACE VIEW vw_return_loss AS
    SELECT 
        r.return_id,
        r.order_id,
        r.product_id,
        p.category,
        r.return_date,
        r.return_reason,
        r.restocked,
        r.return_quantity,
        r.refund_amount,
        r.return_shipping_cost,
        ROUND(CASE
                    WHEN r.restocked = 'Y' THEN r.refund_amount - r.return_quantity * i.unit_cost
                    ELSE r.refund_amount
                END + r.return_shipping_cost,
                2) AS return_loss
    FROM
        fact_returns r
            JOIN
        fact_order_items i ON i.order_item_id = r.order_item_id
            JOIN
        dim_product p ON p.product_id = r.product_id;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 3. View : Order level shipping and bad debt

CREATE OR REPLACE VIEW vw_order_leakage AS
    SELECT 
        o.order_id,
        o.order_date,
        o.customer_id,
        o.salesperson_id,
        o.location_id,
        o.ship_mode,
        o.payment_status,
        o.shipping_cost,
        o.shipping_fee_collected,
        SUM(i.net_sales) AS order_sales,
        SUM(i.line_profit) AS order_profit,
        o.shipping_cost - o.shipping_fee_collected AS shipping_loss,
        CASE
            WHEN o.payment_status = 'Written Off' THEN SUM(i.net_sales)
            ELSE 0
        END AS bad_debt_loss
    FROM
        fact_orders o
            JOIN
        fact_order_items i ON i.order_id = o.order_id
    GROUP BY o.order_id , o.order_date , o.customer_id , o.salesperson_id , o.location_id , o.ship_mode , o.payment_status , o.shipping_cost , o.shipping_fee_collected;
         
-- ---------------------------------------------------------------------------------------------------------------

-- Step 4. View : Customer RFM + churn ( last date 2025-12-31)

CREATE OR REPLACE VIEW vw_customer_rfm AS
WITH base AS (
  SELECT o.customer_id, MAX(o.order_date) AS last_order,
         COUNT(DISTINCT o.order_id) AS frequency,
         SUM(i.net_sales) AS monetary, SUM(i.line_profit) AS profit
  FROM fact_orders o JOIN fact_order_items i ON i.order_id = o.order_id
  GROUP BY o.customer_id),
scored AS (
  SELECT b.*, DATEDIFF('2025-12-31', last_order) AS recency_days,
         NTILE(4) OVER (ORDER BY last_order) AS r_score,
         NTILE(4) OVER (ORDER BY frequency)  AS f_score,
         NTILE(4) OVER (ORDER BY monetary)   AS m_score
  FROM base b)
SELECT s.*,
  CASE WHEN r_score=4 AND f_score>=3 AND m_score>=3 THEN 'Champions'
       WHEN r_score>=3 AND f_score>=2 THEN 'Loyal'
       WHEN r_score=1 AND m_score>=3 THEN 'At Risk (big spenders)'
       WHEN r_score=1 THEN 'Lost'
       ELSE 'Regular' END AS rfm_segment,
  CASE WHEN recency_days > 180 THEN 'Churned' ELSE 'Active' END AS churn_status
FROM scored s;

-- ---------------------------------------------------------------------------------------------------------------

-- Step 5. View 

CREATE OR REPLACE VIEW vw_return_loss AS
SELECT r.return_id, r.order_id, o.customer_id, o.salesperson_id, o.location_id, o.order_date,
       r.product_id, p.category, r.return_date, r.return_reason, r.restocked,
       r.return_quantity, r.refund_amount, r.return_shipping_cost,
       ROUND(CASE WHEN r.restocked='Y' THEN r.refund_amount - r.return_quantity*i.unit_cost
                  ELSE r.refund_amount END + r.return_shipping_cost, 2) AS return_loss
FROM fact_returns r
JOIN fact_order_items i ON i.order_item_id = r.order_item_id
JOIN fact_orders o ON o.order_id = r.order_id
JOIN dim_product p ON p.product_id = r.product_id;

CREATE OR REPLACE VIEW vw_payment_behavior AS
SELECT customer_id, COUNT(*) AS credit_orders,
       ROUND(AVG(DATEDIFF(paid_date, due_date)),1) AS avg_delay_days,
       SUM(payment_status='Written Off') AS written_off_orders
FROM fact_orders WHERE payment_terms_days > 0 GROUP BY customer_id;


-- ------------------------- -- ------------------------- -- --------------------------- -- ----------------------------- -- ---------------------------- -- ---------------------------- -- --------