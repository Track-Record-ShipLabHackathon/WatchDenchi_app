package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHTTPPredictor(t *testing.T) {
	input := PredictionInput{StartedAt: "2026-11-19T10:00:00+09:00", Type: "単3", Chemical: "アルカリ", BatteryQuantity: 1, Manufacturer: "テスト"}
	for _, tc := range []struct {
		name      string
		status    int
		body      string
		wantError bool
	}{
		{"valid", 200, `{"recommended_replacement_date":"2028-07-23"}`, false},
		{"unsupported", 422, `{"detail":{"code":"unsupported_configuration"}}`, true},
		{"server_error", 500, `{}`, true},
		{"bad_json", 200, `not-json`, true},
		{"missing_date", 200, `{}`, true},
		{"bad_date", 200, `{"recommended_replacement_date":"2028-02-30"}`, true},
		{"trailing_json", 200, `{"recommended_replacement_date":"2028-07-23"}{}`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != "POST" || r.URL.Path != "/predict" {
					t.Error("incorrect upstream endpoint")
				}
				if r.Header.Get("Authorization") != "" {
					t.Error("client authentication must not be forwarded")
				}
				var got map[string]any
				if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
					t.Error(err)
				}
				if len(got) != 5 || got["chemical"] != "アルカリ" || got["battery_quantity"] != float64(1) {
					t.Errorf("incorrect input: %v", got)
				}
				w.WriteHeader(tc.status)
				_, _ = w.Write([]byte(tc.body))
			}))
			defer server.Close()
			date, err := NewHTTPPredictor(server.URL).Predict(context.Background(), input)
			if (err != nil) != tc.wantError {
				t.Fatalf("error=%v; wantError=%v", err, tc.wantError)
			}
			if err == nil && (date.In(japanTime).Format("2006-01-02") != "2028-07-23" || date.Hour() != 0) {
				t.Fatalf("wrong JST date: %v", date)
			}
		})
	}
	t.Run("unconfigured", func(t *testing.T) {
		_, err := NewHTTPPredictor("").Predict(context.Background(), input)
		if err == nil {
			t.Fatal("expected configuration error")
		}
	})
	t.Run("canceled", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		_, err := NewHTTPPredictor("http://127.0.0.1:1").Predict(ctx, input)
		if err == nil {
			t.Fatal("expected request cancellation")
		}
	})
}

func TestReadJSON(t *testing.T) {
	for _, body := range []string{`{"id":1,"unknown":true}`, `{"id":1}{"id":2}`, `{"id":1.5}`, strings.Repeat("x", 17000)} {
		r := httptest.NewRequest("POST", "/", strings.NewReader(body))
		w := httptest.NewRecorder()
		var input struct {
			ID int64 `json:"id"`
		}
		if err := readJSON(w, r, &input); err == nil {
			t.Errorf("accepted invalid JSON: %.40s", body)
		}
	}
}
