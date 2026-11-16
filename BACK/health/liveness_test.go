package health

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestLiveness(t *testing.T) {
	request := httptest.NewRequest("GET", "/healthz", nil)
	response := httptest.NewRecorder()

	Liveness(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("HTTP status = %d, want %d", response.Code, http.StatusOK)
	}

	var body map[string]string
	
	err := json.NewDecoder(response.Body).Decode(&body)
	if err != nil {
		t.Fatalf("decode response: %v", err)
	} else if body["status"] != "ok" {
		t.Errorf("status = %q, want %q", body["status"], "ok")
	}
}