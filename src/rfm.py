import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler


def compute_rfm(df, snapshot_date=None):
    # Snapshot date = the day after the last order in the data ('today' for the analysis).
    if snapshot_date is None:
        snapshot_date = df['order_purchase_timestamp'].max() + pd.Timedelta(days=1)
    g = df.groupby('customer_unique_id').agg(
        last_order=('order_purchase_timestamp', 'max'),
        frequency=('order_id', 'nunique'),
        monetary=('payment_total', 'sum'),
    ).reset_index()
    g['recency'] = (snapshot_date - g['last_order']).dt.days
    return g[['customer_unique_id', 'recency', 'frequency', 'monetary']]


def scale_rfm(rfm):
    logged = np.log1p(rfm[['recency', 'frequency', 'monetary']])
    return StandardScaler().fit_transform(logged)


def find_best_k(X, k_range=range(2, 9)):
    rows = []
    for k in k_range:
        km = KMeans(n_clusters=k, n_init=10, random_state=42).fit(X)
        sil = silhouette_score(X, km.labels_, sample_size=10000, random_state=42)
        rows.append({'k': k, 'inertia': km.inertia_, 'silhouette': sil})
    return pd.DataFrame(rows)


def fit_segments(X, k):
    return KMeans(n_clusters=k, n_init=10, random_state=42).fit_predict(X)


def label_segments(rfm, names):
    # names is a dict like {0: 'Champions', 1: 'At Risk'}
    out = rfm.copy()
    out['segment'] = out['cluster'].map(names)
    return out