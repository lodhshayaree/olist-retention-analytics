import numpy as np
import pandas as pd
import shap
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.model_selection import RandomizedSearchCV, StratifiedKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier


def train_baseline(X_train, y_train):
    # Simple model to beat. class_weight='balanced' handles the 3% imbalance.
    m = make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000, class_weight='balanced'))
    return m.fit(X_train, y_train)


def tune(X_train, y_train, n_iter=15):
    spw = (y_train == 0).sum() / (y_train == 1).sum()   # scale_pos_weight for imbalance
    grid = {
        'n_estimators': [150, 300, 500],
        'max_depth': [3, 4, 5, 6],
        'learning_rate': [0.01, 0.03, 0.05, 0.1],
        'subsample': [0.7, 0.8, 1.0],
        'colsample_bytree': [0.6, 0.8, 1.0],
        'min_child_weight': [1, 5, 10],
    }
    base = XGBClassifier(scale_pos_weight=spw, eval_metric='aucpr', random_state=42, n_jobs=-1)
    search = RandomizedSearchCV(base, grid, n_iter=n_iter, scoring='average_precision',
                                cv=StratifiedKFold(3, shuffle=True, random_state=42),
                                random_state=42, verbose=1)
    search.fit(X_train, y_train)
    return search.best_estimator_, search.best_params_


def evaluate(model, X, y, top_pct=0.2):
    p = model.predict_proba(X)[:, 1]
    y = np.asarray(y)
    k = int(len(p) * top_pct)
    top = np.argsort(-p)[:k]
    precision_top = y[top].mean()
    return {
        'roc_auc': roc_auc_score(y, p),
        'pr_auc': average_precision_score(y, p),
        'base_rate': y.mean(),
        'precision_in_top_20pct': precision_top,
        'share_of_repeaters_captured_in_top_20pct': y[top].sum() / y.sum(),
        'lift_in_top_20pct': precision_top / y.mean(),
    }


def explain_shap(model, X_sample):
    return shap.TreeExplainer(model)(X_sample)


def score_customers(model, X, calibrator=None):
    # repeat_probability: chance of a 2nd order in 180 days. repeat_decile: 10 = most likely to return.
    raw = model.predict_proba(X)[:, 1]
    prob = calibrator.predict(raw) if calibrator is not None else raw
    decile = pd.qcut(pd.Series(raw).rank(method='first'), 10, labels=range(1, 11)).astype(int)
    return pd.DataFrame({'repeat_probability': prob, 'repeat_decile': decile.values}, index=X.index)