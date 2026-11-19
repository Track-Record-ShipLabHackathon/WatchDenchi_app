package main

import (
	"net/http"
	"net/url"
	"os"
	"strconv"
)

const productionOrigin = "https://track-record-shiplabhackathon.github.io"

// Local browser origins are opt-in on the Go server receiving the request.
func isAllowedOrigin(origin string) bool {
	if origin == productionOrigin {
		return true
	}
	if os.Getenv("WATCHDENCHI_ALLOW_LOCALHOST_CORS") != "true" {
		return false
	}

	u, err := url.Parse(origin)
	if err != nil || u.Scheme != "http" || u.User != nil || u.Opaque != "" ||
		u.Path != "" || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" {
		return false
	}
	host := u.Hostname()
	if host != "localhost" && host != "127.0.0.1" {
		return false
	}

	// Compare the whole origin too, rejecting empty ports, fragments and brackets.
	port := u.Port()
	if port == "" {
		return origin == "http://"+host
	}
	number, err := strconv.ParseUint(port, 10, 16)
	if err != nil || number == 0 {
		return false
	}
	return origin == "http://"+host+":"+port
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Add("Vary", "Origin")
		origin := r.Header.Get("Origin")

		if origin != "" {
			if !isAllowedOrigin(origin) {
				http.Error(w, "origin not allowed", http.StatusForbidden)
				return
			}
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		}

		if r.Method == http.MethodOptions {
			if origin == "" {
				http.Error(w, "missing origin", http.StatusBadRequest)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
