from pathlib import Path
import pandas as pd
from sqlalchemy import text
from src.db import get_engine

RAW = Path('data/raw')
FILES = {
    'olist_customers_dataset.csv': ('customers', []),
    'olist_orders_dataset.csv': ('orders', ['order_purchase_timestamp', 'order_approved_at', 'order_delivered_carrier_date', 'order_delivered_customer_date', 'order_estimated_delivery_date']),
    'olist_order_items_dataset.csv': ('order_items', ['shipping_limit_date']),
    'olist_order_payments_dataset.csv': ('order_payments', []),
    'olist_order_reviews_dataset.csv': ('order_reviews', ['review_creation_date', 'review_answer_timestamp']),
    'olist_products_dataset.csv': ('products', []),
    'olist_sellers_dataset.csv': ('sellers', []),
    'olist_geolocation_dataset.csv': ('geolocation', []),
    'product_category_name_translation.csv': ('category_translation', []),
}
ZIPS = {'customer_zip_code_prefix': str, 'seller_zip_code_prefix': str, 'geolocation_zip_code_prefix': str}

engine = get_engine()

# Empty all tables first so you can safely re-run this script.
with engine.begin() as conn:
    conn.execute(text('TRUNCATE ' + ', '.join(t for t, _ in FILES.values())))

for fname, (table, date_cols) in FILES.items():
    df = pd.read_csv(RAW / fname, parse_dates=date_cols, dtype=ZIPS)
    df.to_sql(table, engine, if_exists='append', index=False, chunksize=5000, method='multi')
    print('loaded', table, len(df))

print('DONE')