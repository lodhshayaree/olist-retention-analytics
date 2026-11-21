CREATE VIEW vw_orders_clean AS
WITH pay AS (
  SELECT order_id,
         SUM(payment_value) AS payment_total,
         MAX(payment_installments) AS installments,
         (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS main_payment_type
  FROM order_payments GROUP BY order_id
),
items AS (
  SELECT order_id,
         SUM(price) AS items_value,
         SUM(freight_value) AS freight_total,
         COUNT(*) AS n_items
  FROM order_items GROUP BY order_id
),
rev AS (
  SELECT DISTINCT ON (order_id) order_id, review_score
  FROM order_reviews
  ORDER BY order_id, review_answer_timestamp DESC
)
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_purchase_timestamp,
       o.order_delivered_customer_date,
       o.order_estimated_delivery_date,
       (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS delivery_delay_days,
       (o.order_delivered_customer_date::date - o.order_purchase_timestamp::date) AS delivery_days,
       i.items_value, i.freight_total, i.n_items,
       p.payment_total, p.installments, p.main_payment_type,
       r.review_score
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN items i ON i.order_id = o.order_id
LEFT JOIN pay p ON p.order_id = o.order_id
LEFT JOIN rev r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

CREATE VIEW vw_items_clean AS
SELECT oi.order_id, oi.order_item_id, oi.product_id, oi.seller_id,
       oi.price, oi.freight_value,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
LEFT JOIN products p ON p.product_id = oi.product_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

CREATE VIEW vw_customer_orders AS
SELECT customer_unique_id,
       MIN(order_purchase_timestamp) AS first_order_date,
       MAX(order_purchase_timestamp) AS last_order_date,
       COUNT(*) AS n_orders,
       SUM(payment_total) AS total_spend
FROM vw_orders_clean
GROUP BY customer_unique_id;

CREATE VIEW vw_order_product_features AS
SELECT oi.order_id,
       (ARRAY_AGG(COALESCE(t.product_category_name_english, 'unknown') ORDER BY oi.price DESC))[1] AS main_category,
       AVG(p.product_photos_qty) AS avg_photos,
       SUM(p.product_weight_g) AS total_weight_g,
       BOOL_OR(s.seller_state = c.customer_state) AS same_state
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN products p ON p.product_id = oi.product_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
LEFT JOIN sellers s ON s.seller_id = oi.seller_id
GROUP BY oi.order_id;