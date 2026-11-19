"""Run against a separately started service: python tests/smoke_http.py URL --report PATH."""

import argparse
from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path
import urllib.error
import urllib.request


def run(base_url: str) -> dict:
    with urllib.request.urlopen(base_url + "/healthz", timeout=10) as response:
        health = json.load(response)
    assert health["status"] == "ok"
    today = datetime.now(timezone(timedelta(hours=9))).date()
    results = []
    for size, quantity in [("AA", 1), ("AAA", 1), ("AAA", 2)]:
        payload = dict(started_at=today.isoformat(), type=size, chemical="alkaline",
                       battery_quantity=quantity, manufacturer="Panasonic")
        request = urllib.request.Request(
            base_url + "/predict", data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"}, method="POST",
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            assert response.status == 200
            body = json.load(response)
        expected = (today + timedelta(days=body["estimated_service_days"])).isoformat()
        assert body["recommended_replacement_date"] == expected
        assert date.fromisoformat(body["recommended_replacement_date"]).isoformat() == expected
        assert body["normalized_input"]["manufacturer"] == payload["manufacturer"]
        results.append({"request": payload, "response": body})

    invalid = dict(payload, chemical="manganese")
    request = urllib.request.Request(
        base_url + "/predict", data=json.dumps(invalid).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=10)
        raise AssertionError("Unsupported chemistry incorrectly accepted")
    except urllib.error.HTTPError as error:
        assert error.code == 422
        failure = json.load(error)
        assert failure["detail"]["code"] == "unsupported_chemical"
    return {"passed": True, "transport": "real_HTTP_to_separate_uvicorn_process",
            "as_of": today.isoformat(), "health": health, "valid_predictions": results,
            "unsupported_chemistry": failure}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("base_url")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = run(args.base_url.rstrip("/"))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "transport": report["transport"],
                      "dates": [item["response"]["recommended_replacement_date"] for item in report["valid_predictions"]]}))
