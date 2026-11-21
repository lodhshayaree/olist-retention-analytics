CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_customers_unique ON customers(customer_unique_id);
CREATE INDEX idx_items_seller ON order_items(seller_id);
CREATE INDEX idx_items_product ON order_items(product_id);
CREATE INDEX idx_reviews_order ON order_reviews(order_id);

-- Verify row counts
SELECT 'customers' t, COUNT(*) FROM customers UNION ALL
SELECT 'orders', COUNT(*) FROM orders UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews UNION ALL
SELECT 'products', COUNT(*) FROM products UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers UNION ALL
SELECT 'geolocation', COUNT(*) FROM geolocation UNION ALL
SELECT 'category_translation', COUNT(*) FROM category_translation;

-- The key gotcha: orders have one customer_id each, but fewer real people
SELECT COUNT(DISTINCT customer_id) AS ids, COUNT(DISTINCT customer_unique_id) AS real_customers FROM customers;