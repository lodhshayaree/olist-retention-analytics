import numpy as np
import pandas as pd
from src.db import read_sql

DATE_COLS = ['order_purchase_timestamp', 'order_delivered_customer_date', 'order_estimated_delivery_date']


def load_clean_orders():
    # Read the cleaned view from PostgreSQL and tidy it for Python.
    df = read_sql('SELECT * FROM vw_orders_clean')
    for c in DATE_COLS:
        df[c] = pd.to_datetime(df[c])
    df = df.drop_duplicates(subset='order_id')
    return handle_missing(df)


def handle_missing(df):
    df = df.copy()
    df['no_review_flag'] = df['review_score'].isna().astype(int)
    df['review_score'] = df['review_score'].fillna(df['review_score'].median())
    for c in ['items_value', 'freight_total', 'payment_total', 'n_items', 'installments']:
        df[c] = df[c].fillna(0)
    df['main_payment_type'] = df['main_payment_type'].fillna('unknown')
    return df


def cap_outliers(df, cols, q=0.99):
    # Cut extreme values at the 99th percentile so a few huge orders don't distort charts.
    df = df.copy()
    for c in cols:
        df[c] = df[c].clip(upper=df[c].quantile(q))
    return df