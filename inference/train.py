"""Train on source-backed published reference lives, never on invented outcomes."""

from __future__ import annotations

import csv
import hashlib
import json
import platform
from pathlib import Path
from statistics import mean

import sklearn
from sklearn.dummy import DummyRegressor
from sklearn.model_selection import LeaveOneGroupOut
from sklearn.tree import DecisionTreeRegressor

from predictor import feature_vector, predict_tree

ROOT = Path(__file__).resolve().parent
DATA_PATH = ROOT / "data" / "mouse_specs.csv"
MODEL_DIR = ROOT / "model"


def load_rows() -> list[dict]:
    with DATA_PATH.open(encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    seen = set()
    for row in rows:
        identity = (row["mouse_manufacturer"], row["model_family"])
        if identity in seen:
            raise ValueError(f"Duplicate product family: {identity}")
        seen.add(identity)
        row["battery_quantity"] = int(row["battery_quantity"])
        row["service_days"] = float(row["service_days"])
        if row["chemical"] != "alkaline" or row["battery_manufacturer"] != "unknown":
            raise ValueError("Revisit feature design before adding new chemistry or known battery brands")
        if float(row["pc_hours_per_day"]) != 8 or float(row["mouse_active_fraction"]) != 0.05:
            raise ValueError("Do not mix different usage conditions")
        if row["type"] not in {"AA", "AAA"} or row["service_days"] <= 0:
            raise ValueError("Invalid training record")
    return rows


def new_estimator() -> DecisionTreeRegressor:
    # Fixed before evaluation. Leaf medians minimize absolute error on these sparse specifications.
    return DecisionTreeRegressor(criterion="absolute_error", max_depth=2, random_state=42)


def group_name(row: dict) -> str:
    family = row["model_family"]
    if row["mouse_manufacturer"] == "BUFFALO" and "500" in family:
        return "BUFFALO_500_family"
    if row["mouse_manufacturer"] == "BUFFALO" and "115" in family:
        return "BUFFALO_115_family"
    return row["mouse_manufacturer"] + ":" + family


def train(output_dir: Path = MODEL_DIR) -> dict:
    rows = load_rows()
    x = [feature_vector(row["type"], row["battery_quantity"]) for row in rows]
    y = [row["service_days"] for row in rows]
    groups = [group_name(row) for row in rows]
    held_out = []
    for train_ids, test_ids in LeaveOneGroupOut().split(x, y, groups):
        train_x = [x[int(i)] for i in train_ids]
        train_y = [y[int(i)] for i in train_ids]
        estimator = new_estimator().fit(train_x, train_y)
        baseline = DummyRegressor(strategy="median").fit(train_x, train_y)
        for index in test_ids:
            i = int(index)
            held_out.append({
                "model_family": rows[i]["model_family"], "group": groups[i], "actual_published_days": y[i],
                "predicted_days": float(estimator.predict([x[i]])[0]),
                "baseline_days": float(baseline.predict([x[i]])[0]),
            })
    model_mae = mean(abs(row["predicted_days"] - row["actual_published_days"]) for row in held_out)
    baseline_mae = mean(abs(row["baseline_days"] - row["actual_published_days"]) for row in held_out)
    evaluation = {
        "target": "published_reference_service_days_not_observed_replacement_days",
        "method": "leave_one_product_family_out", "rows": len(rows), "groups": len(set(groups)),
        "model_mae_days": model_mae, "median_baseline_mae_days": baseline_mae,
        "better_than_baseline": model_mae < baseline_mae,
        "real_world_replacement_accuracy_validated": False,
        "notes": [
            "Maximum/reference specification labels are mixed and are not measured user lifetimes.",
            "Battery size is confounded with mouse manufacturer in this small convenience sample.",
            "No random rows, synthetic lifetimes, or product model identifiers are used as prediction features.",
        ],
        "held_out_predictions": held_out,
    }
    estimator = new_estimator().fit(x, y)
    raw = estimator.tree_
    tree = {
        "children_left": raw.children_left.tolist(), "children_right": raw.children_right.tolist(),
        "feature": raw.feature.tolist(), "threshold": raw.threshold.tolist(),
        "value": [float(v[0][0]) for v in raw.value],
    }
    for features, prediction in zip(x, estimator.predict(x)):
        if abs(predict_tree(tree, features) - float(prediction)) > 1e-9:
            raise AssertionError("Exported tree prediction differs from scikit-learn")
    support = {}
    for row in rows:
        key = f"{row['type']}:{row['chemical']}:{row['battery_quantity']}"
        support.setdefault(key, []).append(row)
    support = {
        key: {
            "count": len(records),
            "published_min_days": min(row["service_days"] for row in records),
            "published_max_days": max(row["service_days"] for row in records),
            "range_meaning": "observed_specification_range_not_a_prediction_interval",
            "sources": sorted({row["source_url"] for row in records}),
        } for key, records in support.items()
    }
    artifact = {
        "model_version": "mouse-spec-tree-v1", "model_kind": "sklearn.DecisionTreeRegressor",
        "target": evaluation["target"], "feature_names": ["is_AAA", "battery_quantity"],
        "training_rows": len(rows), "training_groups": len(set(groups)),
        "data_sha256": hashlib.sha256(DATA_PATH.read_text(encoding="utf-8").encode("utf-8")).hexdigest(),
        "python_version": platform.python_version(), "sklearn_version": sklearn.__version__,
        "assumptions": [
            "新品の同種類・同状態の電池を同時に入れたものとします。",
            "1日8時間のPC利用のうち5%（24分）をマウス操作に使う条件です。",
            "温度・自動スリープ・接続方式・自然放電による違いは個別に推定しません。",
            "公表された最大値・参考値から学習した交換日の目安で、寿命の保証ではありません。",
            "推奨日は予測した参考日数を装着日に足します。追加の早期交換係数は使用しません。",
        ],
        "unsupported_effects": ["battery_manufacturer", "other_chemistries", "actual_usage", "individual_mouse_model"],
        "support": support, "tree": tree,
        "evaluation": {key: value for key, value in evaluation.items() if key != "held_out_predictions"},
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "mouse_tree.json").write_text(json.dumps(artifact, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output_dir / "evaluation.json").write_text(json.dumps(evaluation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in evaluation.items() if key != "held_out_predictions"}, indent=2))
    return artifact


if __name__ == "__main__":
    train()
