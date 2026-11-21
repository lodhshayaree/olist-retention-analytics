-- Q1. Monthly revenue, orders and average order value
SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS month,
       COUNT(*) AS orders,
       ROUND(SUM(payment_total), 2) AS revenue,
       ROUND(AVG(payment_total), 2) AS aov
FROM vw_orders_clean
GROUP BY 1 ORDER BY 1;

-- Q2. Month-over-month growth using LAG (looks at the previous row)
WITH m AS (
  SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS month,
         SUM(payment_total) AS revenue
  FROM vw_orders_clean GROUP BY 1
)
SELECT month, ROUND(revenue, 0) AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 1) AS mom_growth_pct
FROM m ORDER BY month;

-- Q3. Top 10 categories by revenue, share and running total
WITH cat AS (
  SELECT category, SUM(price) AS revenue FROM vw_items_clean GROUP BY 1
)
SELECT category, ROUND(revenue, 0) AS revenue,
       ROUND(100 * revenue / SUM(revenue) OVER (), 2) AS share_pct,
       ROUND(100 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 2) AS running_pct
FROM cat ORDER BY revenue DESC LIMIT 10;

-- Q4. Revenue by state and share (add the first 5 share_pct values for the top-5 share)
WITH s AS (
  SELECT customer_state, SUM(payment_total) AS revenue FROM vw_orders_clean GROUP BY 1
)
SELECT customer_state, ROUND(revenue, 0) AS revenue,
       ROUND(100 * revenue / SUM(revenue) OVER (), 2) AS share_pct,
       RANK() OVER (ORDER BY revenue DESC) AS rnk
FROM s ORDER BY revenue DESC;

-- Q5. One-time vs repeat customers
SELECT CASE WHEN n_orders = 1 THEN 'one-time' ELSE 'repeat' END AS customer_type,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM vw_customer_orders GROUP BY 1;

-- Q6. Repeat purchase rate by acquisition month
SELECT DATE_TRUNC('month', first_order_date)::date AS cohort_month,
       COUNT(*) AS customers,
       SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) AS repeaters,
       ROUND(100.0 * SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM vw_customer_orders GROUP BY 1 ORDER BY 1;

-- Q7. Cohort retention matrix (month_index 0 = first purchase month = 100%)
WITH first_order AS (
  SELECT customer_unique_id,
         DATE_TRUNC('month', MIN(order_purchase_timestamp)) AS cohort_month
  FROM vw_orders_clean GROUP BY 1
),
activity AS (
  SELECT DISTINCT f.cohort_month, o.customer_unique_id,
         ((EXTRACT(YEAR FROM o.order_purchase_timestamp) - EXTRACT(YEAR FROM f.cohort_month)) * 12
          + (EXTRACT(MONTH FROM o.order_purchase_timestamp) - EXTRACT(MONTH FROM f.cohort_month)))::int AS month_index
  FROM vw_orders_clean o
  JOIN first_order f ON f.customer_unique_id = o.customer_unique_id
),
counts AS (
  SELECT cohort_month, month_index, COUNT(*) AS active_customers
  FROM activity GROUP BY 1, 2
)
SELECT cohort_month::date, month_index, active_customers,
       ROUND(100.0 * active_customers /
             FIRST_VALUE(active_customers) OVER (PARTITION BY cohort_month ORDER BY month_index), 2) AS retention_pct
FROM counts ORDER BY 1, 2;

-- Q8. Average and median days between first and second order
WITH ranked AS (
  SELECT customer_unique_id, order_purchase_timestamp AS ts,
         ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS rn
  FROM vw_orders_clean
)
SELECT COUNT(*) AS repeaters,
       ROUND(AVG(EXTRACT(EPOCH FROM (b.ts - a.ts)) / 86400)::numeric, 1) AS avg_days,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (b.ts - a.ts)) / 86400) AS median_days
FROM ranked a
JOIN ranked b ON a.customer_unique_id = b.customer_unique_id AND a.rn = 1 AND b.rn = 2;

-- Q9. Customer lifetime value (total spend) distribution
SELECT ROUND(AVG(total_spend)::numeric, 2) AS mean,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_spend) AS p25,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_spend) AS median,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_spend) AS p75,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY total_spend) AS p90,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_spend) AS p99
FROM vw_customer_orders;

-- Q10. Average review score by delivery-delay bucket
SELECT CASE WHEN delivery_delay_days <= 0 THEN '1 On time or early'
            WHEN delivery_delay_days <= 3 THEN '2 Late 1-3 days'
            WHEN delivery_delay_days <= 7 THEN '3 Late 4-7 days'
            ELSE '4 Late 7+ days' END AS delay_bucket,
       COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_review
FROM vw_orders_clean
WHERE review_score IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- Q11. HEADLINE QUERY: repeat rate by delay bucket of the customer's FIRST order
WITH ranked AS (
  SELECT customer_unique_id, delivery_delay_days,
         ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS rn
  FROM vw_orders_clean
)
SELECT CASE WHEN r.delivery_delay_days <= 0 THEN '1 On time or early'
            WHEN r.delivery_delay_days <= 3 THEN '2 Late 1-3 days'
            WHEN r.delivery_delay_days <= 7 THEN '3 Late 4-7 days'
            ELSE '4 Late 7+ days' END AS delay_bucket,
       COUNT(*) AS customers,
       ROUND(100.0 * AVG(CASE WHEN c.n_orders > 1 THEN 1 ELSE 0 END), 2) AS repeat_rate_pct
FROM ranked r
JOIN vw_customer_orders c ON c.customer_unique_id = r.customer_unique_id
WHERE r.rn = 1
GROUP BY 1 ORDER BY 1;

-- Q12a. Late delivery rate by state
SELECT customer_state, COUNT(*) AS orders,
       ROUND(100.0 * AVG((delivery_delay_days > 0)::int), 2) AS late_pct
FROM vw_orders_clean GROUP BY 1 ORDER BY late_pct DESC;

-- Q12b. Late delivery rate by seller (sellers with at least 30 orders)
WITH os AS (SELECT DISTINCT order_id, seller_id FROM vw_items_clean)
SELECT os.seller_id, COUNT(*) AS orders,
       ROUND(100.0 * AVG((o.delivery_delay_days > 0)::int), 2) AS late_pct
FROM os JOIN vw_orders_clean o ON o.order_id = os.order_id
GROUP BY 1 HAVING COUNT(*) >= 30
ORDER BY late_pct DESC LIMIT 20;

-- Q13. Categories with the worst review scores (at least 100 orders)
SELECT i.category, COUNT(DISTINCT i.order_id) AS orders,
       ROUND(AVG(o.review_score), 2) AS avg_review
FROM vw_items_clean i
JOIN vw_orders_clean o ON o.order_id = i.order_id
WHERE o.review_score IS NOT NULL
GROUP BY 1 HAVING COUNT(DISTINCT i.order_id) >= 100
ORDER BY avg_review LIMIT 10;

-- Q14. Freight as % of order value vs repeat rate (first order)
WITH ranked AS (
  SELECT customer_unique_id, freight_total, items_value,
         ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS rn
  FROM vw_orders_clean WHERE items_value > 0
)
SELECT CASE WHEN r.freight_total / r.items_value < 0.10 THEN '1 Under 10%'
            WHEN r.freight_total / r.items_value < 0.20 THEN '2 10-20%'
            WHEN r.freight_total / r.items_value < 0.40 THEN '3 20-40%'
            ELSE '4 40% or more' END AS freight_share,
       COUNT(*) AS customers,
       ROUND(100.0 * AVG(CASE WHEN c.n_orders > 1 THEN 1 ELSE 0 END), 2) AS repeat_rate_pct
FROM ranked r
JOIN vw_customer_orders c ON c.customer_unique_id = r.customer_unique_id
WHERE r.rn = 1
GROUP BY 1 ORDER BY 1;

-- Q15. Payment type mix and average order value
SELECT main_payment_type, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct,
       ROUND(AVG(payment_total), 2) AS aov
FROM vw_orders_clean WHERE main_payment_type IS NOT NULL
GROUP BY 1 ORDER BY orders DESC;

-- Q16. Installments vs order value
SELECT installments, COUNT(*) AS orders, ROUND(AVG(payment_total), 2) AS avg_order_value
FROM vw_orders_clean WHERE installments IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- Q17. Top 10 sellers by revenue and their late rate
WITH sr AS (SELECT seller_id, SUM(price) AS revenue FROM vw_items_clean GROUP BY 1),
os AS (SELECT DISTINCT order_id, seller_id FROM vw_items_clean),
sl AS (
  SELECT os.seller_id, ROUND(100.0 * AVG((o.delivery_delay_days > 0)::int), 2) AS late_pct
  FROM os JOIN vw_orders_clean o ON o.order_id = os.order_id GROUP BY 1
)
SELECT sr.seller_id, ROUND(sr.revenue, 0) AS revenue, sl.late_pct
FROM sr JOIN sl ON sl.seller_id = sr.seller_id
ORDER BY sr.revenue DESC LIMIT 10;

-- Q18. Seller concentration: share of revenue from the top 10% of sellers
WITH sr AS (SELECT seller_id, SUM(price) AS revenue FROM vw_items_clean GROUP BY 1),
ranked AS (SELECT seller_id, revenue, NTILE(10) OVER (ORDER BY revenue DESC) AS decile FROM sr)
SELECT ROUND(100 * SUM(revenue) FILTER (WHERE decile = 1) / SUM(revenue), 2) AS top10pct_revenue_share
FROM ranked;