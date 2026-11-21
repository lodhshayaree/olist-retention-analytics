import numpy as np
import pandas as pd

NUM = ['items_value', 'n_items', 'freight_total', 'freight_ratio', 'delivery_days',
       'delivery_delay_days', 'is_late', 'review_score', 'no_review_flag', 'installments',
       'payment_total', 'avg_photos', 'total_weight_g', 'same_state', 'purchase_month',
       'purchase_dow', 'is_weekend', 'is_holiday_season']
CAT = ['main_category', 'main_payment_type', 'customer_state', 'delay_bucket']


def get_first_orders(df):
    # One row per customer: their earliest order.
    d = df.sort_values(['customer_unique_id', 'order_purchase_timestamp'])
    return d.drop_duplicates('customer_unique_id', keep='first').copy()


def build_target(df, window_days=180):
    # 1 if the customer places a 2nd order within window_days of the 1st, else 0.
    d = df.sort_values(['customer_unique_id', 'order_purchase_timestamp']).copy()
    d['rn'] = d.groupby('customer_unique_id').cumcount() + 1
    first = d[d['rn'] == 1].set_index('customer_unique_id')['order_purchase_timestamp']
    second = d[d['rn'] == 2].set_index('customer_unique_id')['order_purchase_timestamp']
    gap_days = (second - first.reindex(second.index)).dt.days
    target = (gap_days <= window_days).reindex(first.index, fill_value=False).astype(int)
    return target.rename('repeat_180d')


def add_features(first_orders, product_feats):
    f = first_orders.merge(product_feats, on='order_id', how='left')
    f['freight_ratio'] = np.where(f['items_value'] > 0, f['freight_total'] / f['items_value'], 0)
    f['is_late'] = (f['delivery_delay_days'] > 0).astype(int)
    f['delay_bucket'] = pd.cut(f['delivery_delay_days'], bins=[-999, 0, 3, 7, 999],
                               labels=['on_time', 'late_1_3', 'late_4_7', 'late_7_plus']).astype(str)
    f['avg_photos'] = f['avg_photos'].fillna(f['avg_photos'].median())
    f['total_weight_g'] = f['total_weight_g'].fillna(f['total_weight_g'].median())
    f['main_category'] = f['main_category'].fillna('unknown')
    f['same_state'] = f['same_state'].fillna(False).astype(int)
    ts = f['order_purchase_timestamp']
    f['purchase_month'] = ts.dt.month
    f['purchase_dow'] = ts.dt.dayofweek
    f['is_weekend'] = (f['purchase_dow'] >= 5).astype(int)
    f['is_holiday_season'] = f['purchase_month'].isin([11, 12]).astype(int)
    return f[['customer_unique_id', 'order_purchase_timestamp'] + NUM + CAT]


def apply_cutoff(df, last_date, window_days=180):
    # eligible = 1 only if the customer had a full 180-day window to come back.
    cutoff = last_date - pd.Timedelta(days=window_days)
    out = df.copy()
    out['eligible'] = (out['order_purchase_timestamp'] <= cutoff).astype(int)
    return out


def encode(df, top_n=15):
    # Turn text columns into 0/1 columns the model can read. Rare categories become 'other'.
    d = df.copy()
    top = d['main_category'].value_counts().head(top_n).index
    d['main_category'] = d['main_category'].where(d['main_category'].isin(top), 'other')
    return pd.get_dummies(d, columns=CAT, dtype=int)


def time_split(df, test_fraction=0.2):
    # Earlier customers = train, later customers = test.
    d = df.sort_values('order_purchase_timestamp')
    cut = int(len(d) * (1 - test_fraction))
    return d.iloc[:cut], d.iloc[cut:]