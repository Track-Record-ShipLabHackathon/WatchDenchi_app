"""Verify the public API with fresh anonymous users; never prints tokens."""
import argparse
import json
from datetime import date
from urllib.error import HTTPError
from urllib.request import Request, urlopen

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base_url")
    args = parser.parse_args()
    base = args.base_url.rstrip("/")
    def call(method, path, token=None, payload=None, expected=200):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
        request = Request(base + path, data=data, headers=headers, method=method)
        try:
            with urlopen(request, timeout=90) as response:
                status, body = response.status, response.read()
        except HTTPError as error:
            status, body = error.code, error.read()
        if status != expected:
            raise RuntimeError(f"{method} {path}: HTTP {status}, expected {expected}: {body.decode('utf-8', errors='replace')}")
        return json.loads(body) if body else None

    token_a = call("POST", "/api/client", expected=201)["access_token"]
    token_b = call("POST", "/api/client", expected=201)["access_token"]
    for brand in ("API確認A", "API確認B"):
        call("POST", "/api/battery", token_a, {"type": "単3形", "chemical": "アルカリ",
             "manufacturer": brand, "quantity": 5, "storage_location": "API確認用"}, 201)
    batteries = call("GET", "/api/battery", token_a)
    first = next(item for item in batteries if item["manufacturer"] == "API確認A")
    second = next(item for item in batteries if item["manufacturer"] == "API確認B")
    assert first["chemical"] == "アルカリ" and first["registered_at"]
    device = call("POST", "/api/device", token_a, {"type": "マウス", "name": "API確認用マウス"}, 201)
    call("POST", "/api/device-battery", token_a,
         {"device_id": device["id"], "battery_id": first["id"], "battery_quantity": 1}, 201)
    usage = next(item for item in call("GET", "/api/device-battery", token_a) if item["device_id"] == device["id"])
    prediction = call("GET", f'/api/prediction?device_battery_id={usage["id"]}', token_a)
    date.fromisoformat(prediction["recommended_replacement_date"])
    stock = {item["id"]: item["quantity"] for item in call("GET", "/api/battery", token_a)}
    assert stock[first["id"]] == 4 and stock[second["id"]] == 5
    call("PATCH", "/api/device-battery", token_a, {"id": usage["id"], "battery_id": second["id"]}, 204)
    stock = {item["id"]: item["quantity"] for item in call("GET", "/api/battery", token_a)}
    assert stock[first["id"]] == 4 and stock[second["id"]] == 4
    replaced = next(item for item in call("GET", "/api/device-battery", token_a) if item["id"] == usage["id"])
    assert replaced["battery_id"] == second["id"]
    call("GET", f'/api/prediction?device_battery_id={usage["id"]}', token_b, expected=404)
    call("PATCH", "/api/device-battery", token_b, {"id": usage["id"], "battery_id": second["id"]}, 404)
    call("GET", "/api/battery", expected=401)
    print("PASS: registration, installation, prediction, replacement, stock counts, user isolation")
    print("Recommended replacement date:", prediction["recommended_replacement_date"])

if __name__ == "__main__":
    main()
