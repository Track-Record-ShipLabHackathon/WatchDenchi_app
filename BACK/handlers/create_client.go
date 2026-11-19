package handlers

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"time"
)

func CreateClient(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if db == nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}

		token := rand.Text()
		tokenHash := sha256.Sum256([]byte(token))

		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()

		const query = `INSERT INTO client (token_hash) VALUES ($1)`
		if _, err := db.ExecContext(ctx, query, tokenHash[:]); err != nil {
			log.Printf("create client: %v", err)
			http.Error(w, "could not create client", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(map[string]string{"access_token": token})
	}
}
