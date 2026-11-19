package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAllowedOriginsDefault(t *testing.T) {
	for _, setting := range []string{"", "false", "TRUE", "1"} {
		t.Run(setting, func(t *testing.T) {
			t.Setenv("WATCHDENCHI_ALLOW_LOCALHOST_CORS", setting)
			if !isAllowedOrigin(productionOrigin) {
				t.Fatal("production origin must remain allowed")
			}
			for _, origin := range []string{"http://localhost:54332", "http://127.0.0.1:8080", "null", "https://example.com"} {
				if isAllowedOrigin(origin) {
					t.Errorf("unexpected allowed origin: %q", origin)
				}
			}
		})
	}
}

func TestAllowedOriginsDevelopment(t *testing.T) {
	t.Setenv("WATCHDENCHI_ALLOW_LOCALHOST_CORS", "true")
	for _, origin := range []string{
		productionOrigin,
		"http://localhost",
		"http://localhost:54332",
		"http://localhost:8080",
		"http://127.0.0.1",
		"http://127.0.0.1:54333",
		"http://127.0.0.1:65535",
	} {
		t.Run(origin, func(t *testing.T) {
			if !isAllowedOrigin(origin) {
				t.Errorf("expected allowed origin: %q", origin)
			}
		})
	}
	for _, origin := range []string{
		"",
		"null",
		"https://example.com",
		"https://localhost:54332",
		"http://localhost.attacker.example:54332",
		"http://127.0.0.1.attacker.example",
		"http://localhost@attacker.example",
		"http://attacker.example@localhost",
		"http://localhost:54332/",
		"http://localhost:54332/path",
		"http://localhost:54332?value=1",
		"http://localhost:54332?",
		"http://localhost:54332#value",
		"http://localhost:54332#",
		"http://localhost:",
		"http://localhost:0",
		"http://localhost:65536",
		"http://localhost:abc",
		"http://[localhost]:54332",
		"http://[::1]:54332",
		"//localhost:54332",
		"http:localhost:54332",
		"https://track-record-shiplabhackathon.github.io.attacker.example",
	} {
		t.Run(origin, func(t *testing.T) {
			if isAllowedOrigin(origin) {
				t.Errorf("unexpected allowed origin: %q", origin)
			}
		})
	}
}

func checkPreflight(t *testing.T, origin string, wantStatus int) {
	t.Helper()
	called := false
	handler := withCORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	}))
	request := httptest.NewRequest(http.MethodOptions, "/api/device-battery", nil)
	if origin != "" {
		request.Header.Set("Origin", origin)
	}
	request.Header.Set("Access-Control-Request-Method", "PATCH")
	request.Header.Set("Access-Control-Request-Headers", "authorization, content-type")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != wantStatus {
		t.Fatalf("status = %d, want %d", response.Code, wantStatus)
	}
	if called {
		t.Fatal("preflight must not reach authentication or database handlers")
	}
	if response.Header().Get("Vary") != "Origin" {
		t.Fatal("response must vary by Origin")
	}
	if wantStatus != http.StatusNoContent {
		if response.Header().Get("Access-Control-Allow-Origin") != "" {
			t.Fatal("rejected origin must not receive an allow-origin header")
		}
		return
	}
	if response.Header().Get("Access-Control-Allow-Origin") != origin {
		t.Fatal("allow-origin must match the exact requesting origin")
	}
	if response.Header().Get("Access-Control-Allow-Methods") != "GET, POST, PATCH" {
		t.Fatal("preflight must allow the existing API methods")
	}
	if response.Header().Get("Access-Control-Allow-Headers") != "Authorization, Content-Type" {
		t.Fatal("preflight must permit Bearer authentication and JSON")
	}
	if response.Header().Get("Access-Control-Allow-Credentials") != "" {
		t.Fatal("cookie credentials are not needed")
	}
}

func TestCORSPreflight(t *testing.T) {
	t.Setenv("WATCHDENCHI_ALLOW_LOCALHOST_CORS", "")
	checkPreflight(t, productionOrigin, http.StatusNoContent)
	checkPreflight(t, "http://localhost:54332", http.StatusForbidden)
	checkPreflight(t, "", http.StatusBadRequest)

	t.Setenv("WATCHDENCHI_ALLOW_LOCALHOST_CORS", "true")
	checkPreflight(t, productionOrigin, http.StatusNoContent)
	checkPreflight(t, "http://localhost:54332", http.StatusNoContent)
	checkPreflight(t, "http://127.0.0.1:8080", http.StatusNoContent)
	checkPreflight(t, "http://localhost.attacker.example:54332", http.StatusForbidden)
}

func TestCORSActualRequests(t *testing.T) {
	t.Setenv("WATCHDENCHI_ALLOW_LOCALHOST_CORS", "true")
	for _, origin := range []string{"", productionOrigin, "http://localhost:54332"} {
		t.Run(origin, func(t *testing.T) {
			called := false
			handler := withCORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				called = true
				if r.Header.Get("Authorization") != "Bearer test-token" {
					t.Error("CORS must preserve the authentication header")
				}
				http.Error(w, "unauthorized", http.StatusUnauthorized)
			}))
			request := httptest.NewRequest(http.MethodGet, "/api/battery", nil)
			request.Header.Set("Origin", origin)
			request.Header.Set("Authorization", "Bearer test-token")
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, request)
			if !called || response.Code != http.StatusUnauthorized {
				t.Fatal("allowed request must reach the existing handler")
			}
			if response.Header().Get("Access-Control-Allow-Origin") != origin {
				t.Fatal("even an authentication error must carry the allowed origin")
			}
		})
	}
}
