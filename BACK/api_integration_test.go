package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/Track-Record-ShipLabHackathon/WatchDenchi_app/BACK/handlers"
)

type apiTestClient struct {
	t           *testing.T
	base, token string
}

func (c apiTestClient) request(method, path string, payload any) (int, []byte) {
	c.t.Helper()
	var body io.Reader
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			c.t.Fatal(err)
		}
		body = bytes.NewReader(encoded)
	}
	req, err := http.NewRequest(method, c.base+path, body)
	if err != nil {
		c.t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	response, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer response.Body.Close()
	data, err := io.ReadAll(response.Body)
	if err != nil {
		c.t.Fatal(err)
	}
	return response.StatusCode, data
}
func (c apiTestClient) expect(method, path string, payload any, want int) []byte {
	c.t.Helper()
	status, data := c.request(method, path, payload)
	if status != want {
		c.t.Fatalf("%s %s: status=%d want=%d body=%s", method, path, status, want, data)
	}
	return data
}
func decodeTest[T any](t *testing.T, data []byte) T {
	t.Helper()
	var result T
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatalf("decode %s: %v", data, err)
	}
	return result
}

func integrationDB(t *testing.T) *sql.DB {
	t.Helper()
	dsn := os.Getenv("WATCHDENCHI_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set WATCHDENCHI_TEST_DATABASE_URL for isolated PostgreSQL integration tests")
	}
	admin, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { admin.Close() })
	var name string
	if err := admin.QueryRow("SELECT current_database()").Scan(&name); err != nil {
		t.Fatal(err)
	}
	if name != "watchdenchi_test" {
		t.Fatal("integration tests require a separate database named watchdenchi_test")
	}
	schema := fmt.Sprintf("watchdenchi_test_%d", time.Now().UnixNano())
	if _, err := admin.Exec("CREATE SCHEMA " + schema); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := admin.Exec("DROP SCHEMA " + schema + " CASCADE"); err != nil {
			t.Error(err)
		}
	})
	parsed, err := url.Parse(dsn)
	if err != nil {
		t.Fatal(err)
	}
	query := parsed.Query()
	query.Set("search_path", schema)
	parsed.RawQuery = query.Encode()
	db, err := sql.Open("pgx", parsed.String())
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(5)
	t.Cleanup(func() { db.Close() })
	for _, file := range []string{"0001_create_client.sql", "0002_create_battery.sql", "0003_device_prediction.sql"} {
		data, err := os.ReadFile(filepath.Join("..", "DB", file))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(string(data)); err != nil {
			t.Fatalf("apply %s: %v", file, err)
		}
	}
	return db
}

func TestAPIIntegration(t *testing.T) {
	db := integrationDB(t)
	var failPrediction atomic.Bool
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if failPrediction.Load() {
			http.Error(w, "unavailable", 503)
			return
		}
		var input handlers.PredictionInput
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			t.Error(err)
			http.Error(w, "bad input", 422)
			return
		}
		if input.Chemical != "アルカリ" || input.BatteryQuantity != 1 {
			http.Error(w, "unsupported", 422)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"recommended_replacement_date":"2028-07-23"}`)
	}))
	defer upstream.Close()
	server := httptest.NewServer(newRouter(db, handlers.NewHTTPPredictor(upstream.URL)))
	defer server.Close()
	anonymous := apiTestClient{t: t, base: server.URL}
	newClient := func() apiTestClient {
		item := decodeTest[struct {
			Token string `json:"access_token"`
		}](t, anonymous.expect("POST", "/api/client", nil, 201))
		if item.Token == "" {
			t.Fatal("missing token")
		}
		return apiTestClient{t: t, base: server.URL, token: item.Token}
	}
	a, b := newClient(), newClient()
	anonymous.expect("GET", "/api/battery", nil, 401)
	apiTestClient{t: t, base: server.URL, token: "invalid"}.expect("GET", "/api/battery", nil, 401)
	type battery struct {
		ID           int64   `json:"id"`
		Quantity     int     `json:"quantity"`
		RegisteredAt string  `json:"registered_at"`
		Chemical     *string `json:"chemical"`
	}
	addBattery := func(c apiTestClient, n int) int64 {
		c.expect("POST", "/api/battery", map[string]any{"type": "単3", "chemical": "アルカリ", "manufacturer": "テスト", "quantity": n, "storage_location": ""}, 201)
		items := decodeTest[[]battery](t, c.expect("GET", "/api/battery", nil, 200))
		last := items[len(items)-1]
		if last.RegisteredAt == "" || last.Chemical == nil {
			t.Fatal("missing registered_at or chemical")
		}
		return last.ID
	}
	first, second, foreign := addBattery(a, 5), addBattery(a, 4), addBattery(b, 4)
	if len(decodeTest[[]battery](t, a.expect("GET", "/api/battery", nil, 200))) != 2 {
		t.Fatal("inventory isolation failed")
	}
	newDevice := func(c apiTestClient) int64 {
		item := decodeTest[struct {
			ID           int64  `json:"id"`
			RegisteredAt string `json:"registered_at"`
		}](t, c.expect("POST", "/api/device", map[string]any{"type": "マウス", "name": "机のマウス"}, 201))
		if item.ID < 1 || item.RegisteredAt == "" {
			t.Fatal("incomplete device response")
		}
		return item.ID
	}
	device, foreignDevice := newDevice(a), newDevice(b)
	installation := func(d, batteryID int64) map[string]any {
		return map[string]any{"device_id": d, "battery_id": batteryID, "battery_quantity": 1}
	}
	stock := func(id int64) int {
		t.Helper()
		var n int
		if err := db.QueryRow("SELECT quantity FROM battery WHERE id=$1", id).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	assertStock := func(id int64, want int) {
		t.Helper()
		if n := stock(id); n != want {
			t.Fatalf("battery %d quantity=%d want=%d", id, n, want)
		}
	}

	t.Run("ownership_and_invalid_input", func(t *testing.T) {
		a.expect("POST", "/api/device-battery", installation(device, foreign), 404)
		a.expect("POST", "/api/device-battery", installation(foreignDevice, first), 404)
		b.expect("PATCH", "/api/battery", map[string]any{"id": first, "quantity": 0}, 404)
		a.expect("POST", "/api/device-battery", map[string]any{"device_id": device, "battery_id": first, "battery_quantity": 0}, 400)
		a.expect("POST", "/api/battery", map[string]any{"type": "単3", "manufacturer": "テスト", "quantity": 1}, 400)
		assertStock(first, 5)
		assertStock(foreign, 4)
	})
	t.Run("failed_prediction_keeps_device_and_stock", func(t *testing.T) {
		failPrediction.Store(true)
		a.expect("POST", "/api/device-battery", installation(device, first), 502)
		failPrediction.Store(false)
		assertStock(first, 5)
		if len(decodeTest[[]map[string]any](t, a.expect("GET", "/api/device", nil, 200))) != 1 {
			t.Fatal("unconfigured device was lost")
		}
		if len(decodeTest[[]map[string]any](t, a.expect("GET", "/api/device-battery", nil, 200))) != 0 {
			t.Fatal("failed installation was saved")
		}
	})
	a.expect("POST", "/api/device-battery", installation(device, first), 201)
	assertStock(first, 4)
	type usage struct {
		ID        int64  `json:"id"`
		BatteryID int64  `json:"battery_id"`
		StartedAt string `json:"started_at"`
		Date      string `json:"recommended_replacement_date"`
	}
	usages := decodeTest[[]usage](t, a.expect("GET", "/api/device-battery", nil, 200))
	if len(usages) != 1 || usages[0].Date != "2028-07-23" || usages[0].StartedAt == "" {
		t.Fatalf("incomplete usage: %+v", usages)
	}
	usageID := usages[0].ID
	path := fmt.Sprintf("/api/prediction?device_battery_id=%d", usageID)
	t.Run("duplicate_and_ownership", func(t *testing.T) {
		a.expect("POST", "/api/device-battery", installation(device, first), 409)
		assertStock(first, 4)
		result := decodeTest[map[string]any](t, a.expect("GET", path, nil, 200))
		if result["recommended_replacement_date"] != "2028-07-23" {
			t.Fatal(result)
		}
		b.expect("GET", path, nil, 404)
		b.expect("PATCH", "/api/device-battery", map[string]any{"id": usageID, "battery_id": foreign}, 404)
		a.expect("PATCH", "/api/device-battery", map[string]any{"id": usageID, "battery_id": foreign}, 404)
	})
	a.expect("PATCH", "/api/device-battery", map[string]any{"id": usageID, "battery_id": second}, 204)
	assertStock(first, 4)
	assertStock(second, 3)
	t.Run("failed_replacement_changes_nothing", func(t *testing.T) {
		before := decodeTest[[]usage](t, a.expect("GET", "/api/device-battery", nil, 200))[0]
		failPrediction.Store(true)
		a.expect("PATCH", "/api/device-battery", map[string]any{"id": usageID, "battery_id": first}, 502)
		failPrediction.Store(false)
		assertStock(first, 4)
		assertStock(second, 3)
		after := decodeTest[[]usage](t, a.expect("GET", "/api/device-battery", nil, 200))[0]
		if after != before {
			t.Fatalf("usage changed after failure: before=%+v after=%+v", before, after)
		}
	})
	t.Run("insufficient_stock", func(t *testing.T) {
		a.expect("PATCH", "/api/battery", map[string]any{"id": first, "quantity": 0}, 204)
		a.expect("PATCH", "/api/device-battery", map[string]any{"id": usageID, "battery_id": first}, 409)
		assertStock(first, 0)
		assertStock(second, 3)
	})
	t.Run("database_failure_rolls_back_stock", func(t *testing.T) {
		d := newDevice(a)
		_, err := db.Exec(`CREATE FUNCTION reject_usage() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test failure'; END $$; CREATE TRIGGER reject_usage_trigger BEFORE INSERT ON device_battery FOR EACH ROW EXECUTE FUNCTION reject_usage();`)
		if err != nil {
			t.Fatal(err)
		}
		a.expect("POST", "/api/device-battery", installation(d, second), 500)
		assertStock(second, 3)
		if _, err := db.Exec("DROP TRIGGER reject_usage_trigger ON device_battery; DROP FUNCTION reject_usage();"); err != nil {
			t.Fatal(err)
		}
	})
	t.Run("concurrent_installation_cannot_oversell", func(t *testing.T) {
		onlyOne := addBattery(a, 1)
		d1, d2 := newDevice(a), newDevice(a)
		var wg sync.WaitGroup
		statuses := make(chan int, 2)
		for _, d := range []int64{d1, d2} {
			wg.Add(1)
			go func(id int64) {
				defer wg.Done()
				status, _ := a.request("POST", "/api/device-battery", installation(id, onlyOne))
				statuses <- status
			}(d)
		}
		wg.Wait()
		close(statuses)
		ok, conflict := 0, 0
		for status := range statuses {
			if status == 201 {
				ok++
			} else if status == 409 {
				conflict++
			} else {
				t.Errorf("unexpected concurrent status: %d", status)
			}
		}
		if ok != 1 || conflict != 1 {
			t.Fatalf("success=%d conflict=%d", ok, conflict)
		}
		assertStock(onlyOne, 0)
	})
	t.Run("legacy_chemical_is_not_invented", func(t *testing.T) {
		var id int64
		if err := db.QueryRow("INSERT INTO battery (client_id,type,manufacturer,quantity,storage_location) SELECT id,'単3','legacy',3,'' FROM client LIMIT 1 RETURNING id").Scan(&id); err != nil {
			t.Fatal(err)
		}
		var chemical sql.NullString
		if err := db.QueryRow("SELECT chemical FROM battery WHERE id=$1", id).Scan(&chemical); err != nil {
			t.Fatal(err)
		}
		if chemical.Valid {
			t.Fatal("legacy chemical was guessed")
		}
	})
}

func TestCORSPatch(t *testing.T) {
	handler := newRouter(nil, nil)
	request := httptest.NewRequest("OPTIONS", "/api/device-battery", nil)
	request.Header.Set("Origin", "https://track-record-shiplabhackathon.github.io")
	request.Header.Set("Access-Control-Request-Method", "PATCH")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != 204 || !strings.Contains(response.Header().Get("Access-Control-Allow-Methods"), "PATCH") {
		t.Fatalf("PATCH preflight failed: %d %v", response.Code, response.Header())
	}
	request = httptest.NewRequest("GET", "/healthz", nil)
	request.Header.Set("Origin", "https://untrusted.example")
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != 403 {
		t.Fatal("untrusted origin accepted")
	}
}
