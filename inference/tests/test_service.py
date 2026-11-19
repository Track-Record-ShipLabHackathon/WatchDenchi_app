from datetime import date, timedelta
import hashlib
import json
from pathlib import Path
import unittest

from fastapi.testclient import TestClient

from app import app
from predictor import MODEL_PATH, PredictionError, Predictor, parse_started_at, today_jst


class PredictorTests(unittest.TestCase):
    def setUp(self):
        self.predictor = Predictor()

    def estimate(self, **overrides):
        values = dict(started_at="2026-11-19", battery_type="単3", chemical="アルカリ",
                      battery_quantity=1, manufacturer="Panasonic", today=date(2026, 11, 19))
        return self.predictor.predict(**(values | overrides))

    def test_date_is_started_at_plus_learned_days(self):
        result = self.estimate()
        self.assertEqual(result["recommended_replacement_date"],
                         (date(2026, 11, 19) + timedelta(days=result["estimated_service_days"])).isoformat())
        self.assertGreater(result["estimated_service_days"], 0)
        self.assertEqual(result["quality"], "demo_only")
        self.assertNotIn("remaining_percent", result)

    def test_changing_start_date_moves_result_by_same_number_of_days(self):
        first = date.fromisoformat(self.estimate()["recommended_replacement_date"])
        second = date.fromisoformat(self.estimate(started_at="2026-11-18")["recommended_replacement_date"])
        self.assertEqual((first - second).days, 1)

    def test_unsupported_chemistry_and_configuration_have_no_fabricated_result(self):
        for overrides in [dict(chemical="マンガン"), dict(battery_quantity=2), dict(battery_type="単1")]:
            with self.subTest(overrides=overrides), self.assertRaises(PredictionError):
                self.estimate(**overrides)

    def test_no_unsupported_manufacturer_multiplier(self):
        self.assertEqual(self.estimate()["estimated_service_days"],
                         self.estimate(manufacturer="Energizer")["estimated_service_days"])

    def test_battery_count_is_not_multiplied_after_prediction(self):
        one = self.estimate(battery_type="AAA", battery_quantity=1)
        two = self.estimate(battery_type="AAA", battery_quantity=2)
        self.assertNotEqual(two["estimated_service_days"], one["estimated_service_days"] * 2)
        self.assertEqual(two["reference_data"]["count"], 2)

    def test_future_date_rejected(self):
        with self.assertRaises(PredictionError):
            self.estimate(started_at="2026-11-20")

    def test_expired_prediction_is_not_reset_to_today(self):
        result = self.estimate(started_at="2020-01-01")
        self.assertEqual(result["status"], "overdue")
        self.assertEqual(result["days_until_replacement"], 0)
        self.assertLess(date.fromisoformat(result["recommended_replacement_date"]), date(2026, 11, 19))

    def test_dates_and_timezone(self):
        self.assertEqual(parse_started_at("2026-11-18T16:00:00Z"), date(2026, 11, 19))
        self.assertEqual(parse_started_at("2024-02-29"), date(2024, 2, 29))
        for invalid in ["2026-02-30", "2026-11-19T12:00:00", "not-a-date", "20261119"]:
            with self.subTest(invalid=invalid), self.assertRaises(PredictionError):
                parse_started_at(invalid)

    def test_model_matches_committed_training_data(self):
        path = Path(__file__).resolve().parents[1] / "data" / "mouse_specs.csv"
        self.assertEqual(self.predictor.model["data_sha256"], hashlib.sha256(path.read_text(encoding="utf-8").encode("utf-8")).hexdigest())


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.client.__enter__()
        self.payload = dict(started_at=today_jst().isoformat(), type="AA", chemical="alkaline",
                            battery_quantity=1, manufacturer="unknown")

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def test_http_contract_and_health(self):
        self.assertEqual(self.client.get("/healthz").status_code, 200)
        response = self.client.post("/predict", json=self.payload)
        self.assertEqual(response.status_code, 200)
        date.fromisoformat(response.json()["recommended_replacement_date"])
        self.assertEqual(self.client.get("/model").json()["training_rows"], 15)

    def test_invalid_requests(self):
        for overrides in [dict(battery_quantity=0), dict(battery_quantity=True), dict(battery_quantity="1"),
                          dict(manufacturer=""), dict(model_number="M185"), dict(chemical="マンガン")]:
            with self.subTest(overrides=overrides):
                response = self.client.post("/predict", json=self.payload | overrides)
                self.assertEqual(response.status_code, 422)
        missing = dict(self.payload)
        missing.pop("chemical")
        self.assertEqual(self.client.post("/predict", json=missing).status_code, 422)
        self.assertEqual(self.client.post("/predict", content="{broken", headers={"Content-Type": "application/json"}).status_code, 422)


if __name__ == "__main__":
    unittest.main()
