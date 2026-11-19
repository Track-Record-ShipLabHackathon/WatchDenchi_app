"""Inference using a regression tree learned from published mouse specifications."""

from __future__ import annotations

import json
import math
import re
import unicodedata
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

JST = timezone(timedelta(hours=9))
MODEL_PATH = Path(__file__).resolve().parent / "model" / "mouse_tree.json"


class PredictionError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def today_jst() -> date:
    return datetime.now(JST).date()


def normalized_text(value: str) -> str:
    return unicodedata.normalize("NFKC", value).strip().lower()


def normalize_type(value: str) -> str:
    aliases = {
        "aa": "AA", "単3": "AA", "単三": "AA", "単3形": "AA", "単三形": "AA", "lr6": "AA",
        "aaa": "AAA", "単4": "AAA", "単四": "AAA", "単4形": "AAA", "単四形": "AAA", "lr03": "AAA",
    }
    result = aliases.get(normalized_text(value))
    if result is None:
        raise PredictionError("unsupported_battery_type", "この試作は単3・単4のみに対応しています。")
    return result


def normalize_chemical(value: str) -> str:
    if normalized_text(value) in {"alkaline", "アルカリ", "アルカリ乾電池", "アルカリ電池"}:
        return "alkaline"
    raise PredictionError(
        "unsupported_chemical", "対応する寿命データがあるのはアルカリ電池です。化学系を推測して補完しません。"
    )


def parse_started_at(value: str) -> date:
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            return date.fromisoformat(value)
        if not re.match(r"\d{4}-\d{2}-\d{2}T", value):
            raise ValueError("expected date or RFC3339 timestamp")
        timestamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if timestamp.tzinfo is None:
            raise ValueError("timestamp requires a timezone")
        return timestamp.astimezone(JST).date()
    except ValueError as error:
        raise PredictionError(
            "invalid_started_at", "started_atはYYYY-MM-DD、または時差付き日時（例：2026-11-19T10:00:00+09:00）です。"
        ) from error


def feature_vector(battery_type: str, quantity: int) -> list[float]:
    return [float(battery_type == "AAA"), float(quantity)]


def predict_tree(tree: dict, features: list[float]) -> float:
    node = 0
    while tree["children_left"][node] != -1:
        feature = tree["feature"][node]
        node = (
            tree["children_left"][node]
            if features[feature] <= tree["threshold"][node]
            else tree["children_right"][node]
        )
    return float(tree["value"][node])


class Predictor:
    def __init__(self, model_path: Path = MODEL_PATH):
        self.model = json.loads(model_path.read_text(encoding="utf-8"))

    def predict(self, started_at: str, battery_type: str, chemical: str,
                battery_quantity: int, manufacturer: str, *, today: date | None = None) -> dict:
        current = today or today_jst()
        started = parse_started_at(started_at)
        if started > current:
            raise PredictionError("future_started_at", "電池を入れた日を未来の日付にはできません。")
        size = normalize_type(battery_type)
        chemistry = normalize_chemical(chemical)
        if type(battery_quantity) is not int or battery_quantity < 1:
            raise PredictionError("invalid_quantity", "battery_quantityは1以上の整数です。")
        brand = manufacturer.strip()
        if not brand or len(brand) > 100:
            raise PredictionError("invalid_manufacturer", "manufacturerは1～100文字です。不明ならunknownを指定します。")
        key = f"{size}:{chemistry}:{battery_quantity}"
        support = self.model["support"].get(key)
        if support is None:
            raise PredictionError("unsupported_configuration", "このサイズ・化学系・本数の組み合わせは学習データにありません。")

        days = max(1, math.floor(predict_tree(self.model["tree"], feature_vector(size, battery_quantity)) + 0.5))
        recommended = started + timedelta(days=days)
        warnings = [
            "公表仕様を学習したデモ用の目安です。実際の交換日での精度は未検証です。",
            "電池製造元ごとの寿命データがないため、manufacturerによる補正はしていません。",
            "同じ入力条件でもマウスの設計・使い方で寿命が異なります。",
        ]
        if support["count"] < 5:
            warnings.append("この電池構成の資料は5件未満で、根拠が特に少ない状態です。")
        return {
            "device_type": "mouse",
            "recommended_replacement_date": recommended.isoformat(),
            "estimated_service_days": days,
            "days_until_replacement": max(0, (recommended - current).days),
            "status": "overdue" if recommended < current else "due_today" if recommended == current else "estimated",
            "as_of": current.isoformat(),
            "normalized_input": {
                "started_at": started.isoformat(), "type": size, "chemical": chemistry,
                "battery_quantity": battery_quantity, "manufacturer": brand,
            },
            "model_version": self.model["model_version"],
            "method": "trained_decision_tree_regression",
            "quality": "demo_only",
            "learned_fields": ["type", "battery_quantity"],
            "assumptions": self.model["assumptions"],
            "reference_data": support,
            "warnings": warnings,
        }
