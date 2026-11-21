import pandas as pd

SCENARIOS = {
    'conservative': {'assumed_uplift': 0.05, 'coupon_value': 10},
    'base': {'assumed_uplift': 0.10, 'coupon_value': 10},
    'optimistic': {'assumed_uplift': 0.20, 'coupon_value': 10},
}


def campaign_simulation(scores, avg_order_value, top_pct=0.2, coupon_value=10, assumed_uplift=0.10, margin=1.0):
    # assumed_uplift: the coupon raises each targeted customer's repeat chance by this share (0.10 = +10% relative).
    # coupon_value: R$ given to every customer who places a repeat order.
    # margin: share of revenue that is profit. 1.0 = revenue view (as in the plan); try 0.3 for a profit view.
    s = scores.sort_values('repeat_probability', ascending=False)
    n = int(len(s) * top_pct)
    target = s.head(n)
    baseline_orders = target['repeat_probability'].sum()
    incremental_orders = baseline_orders * assumed_uplift
    incremental_revenue = incremental_orders * avg_order_value * margin
    coupon_cost = (baseline_orders + incremental_orders) * coupon_value
    net = incremental_revenue - coupon_cost
    return {
        'customers_targeted': n,
        'expected_baseline_repeat_orders': round(baseline_orders, 1),
        'incremental_orders': round(incremental_orders, 1),
        'incremental_revenue': round(incremental_revenue, 0),
        'coupon_cost': round(coupon_cost, 0),
        'net_benefit': round(net, 0),
        'roi': round(net / coupon_cost, 2) if coupon_cost else None,
    }


def run_scenarios(scores, avg_order_value, top_pct=0.2, margin=1.0):
    rows = []
    for name, p in SCENARIOS.items():
        r = campaign_simulation(scores, avg_order_value, top_pct, margin=margin, **p)
        r['scenario'] = name
        rows.append(r)
    return pd.DataFrame(rows)