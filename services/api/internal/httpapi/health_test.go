package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthEndpoints(t *testing.T) {
	for _, test := range []struct {
		name    string
		path    string
		pingErr error
		code    int
		status  string
	}{
		{"process alive while database is down", "/healthz", errors.New("offline"), 200, "ok"},
		{"database is ready", "/readyz", nil, 200, "ready"},
		{"database is down", "/readyz", errors.New("offline"), 503, "database_unavailable"},
	} {
		t.Run(test.name, func(t *testing.T) {
			handler := NewHandler(func(context.Context) error { return test.pingErr })
			req := httptest.NewRequest(http.MethodGet, test.path, nil)
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != test.code {
				t.Fatalf("HTTP status = %d, want %d", res.Code, test.code)
			}
			var payload map[string]string
			if err := json.NewDecoder(res.Body).Decode(&payload); err != nil {
				t.Fatal(err)
			}
			if payload["status"] != test.status {
				t.Errorf("body status = %q, want %q", payload["status"], test.status)
			}
		})
	}
}
