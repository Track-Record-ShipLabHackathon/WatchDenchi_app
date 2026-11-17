package handlers

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

func RegisterBattery(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if db == nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}

		auth := strings.Fields(r.Header.Get("Authorization"))
		if len(auth) != 2 || !strings.EqualFold(auth[0], "Bearer") {
			writeUnauthorized(w)
			return
		}

		var input struct {
			Type            string `json:"type"`
			Manufacturer    string `json:"manufacturer"`
			Quantity        int32  `json:"quantity"`
			StorageLocation string `json:"storage_location"`
		}

		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 16*1024))
		if err != nil || json.Unmarshal(body, &input) != nil {
			http.Error(w, "invalid request body", http.StatusBadRequest)
			return
		}

		input.Type = strings.TrimSpace(input.Type)
		input.Manufacturer = strings.TrimSpace(input.Manufacturer)
		input.StorageLocation = strings.TrimSpace(input.StorageLocation)
		if input.Type == "" || input.Manufacturer == "" ||
			input.StorageLocation == "" || input.Quantity < 1 {
			http.Error(w, "invalid battery fields", http.StatusBadRequest)
			return
		}

		tokenHash := sha256.Sum256([]byte(auth[1]))
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()

		const query = `
			INSERT INTO battery (client_id, type, manufacturer, quantity, storage_location)
			SELECT id, $2, $3, $4, $5
			FROM client
			WHERE token_hash = $1
			RETURNING id
		`

		var batteryID int64
		err = db.QueryRowContext(ctx, query, tokenHash[:], input.Type,
			input.Manufacturer, input.Quantity, input.StorageLocation).Scan(&batteryID)
		if errors.Is(err, sql.ErrNoRows) {
			writeUnauthorized(w)
			return
		}
		if err != nil {
			log.Printf("register battery: %v", err)
			http.Error(w, "could not register battery", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusCreated)
	}
}

func writeUnauthorized(w http.ResponseWriter) {
	w.Header().Set("WWW-Authenticate", "Bearer")
	http.Error(w, "unauthorized", http.StatusUnauthorized)
}