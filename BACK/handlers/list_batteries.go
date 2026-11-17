package handlers

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"
)

type batteryListItem struct {
	ID              int64     `json:"id"`
	Type            string    `json:"type"`
	Manufacturer    string    `json:"manufacturer"`
	Quantity        int32     `json:"quantity"`
	StorageLocation string    `json:"storage_location"`
	RegistedAt      time.Time `json:"registed_at"`
}

func ListBatteries(db *sql.DB) http.HandlerFunc {
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
		tokenHash := sha256.Sum256([]byte(auth[1]))

		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()

		var clientID int64
		err := db.QueryRowContext(ctx,
			`SELECT id FROM client WHERE token_hash = $1`, tokenHash[:],
		).Scan(&clientID)
		if errors.Is(err, sql.ErrNoRows) {
			writeUnauthorized(w)
			return
		}
		if err != nil {
			log.Printf("list batteries: find client: %v", err)
			http.Error(w, "could not list batteries", http.StatusInternalServerError)
			return
		}

		const query = `
			SELECT id, type, manufacturer, quantity, storage_location, registed_at
			FROM battery
			WHERE client_id = $1
			ORDER BY id
		`
		rows, err := db.QueryContext(ctx, query, clientID)
		if err != nil {
			log.Printf("list batteries: query: %v", err)
			http.Error(w, "could not list batteries", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		batteries := make([]batteryListItem, 0)
		for rows.Next() {
			var item batteryListItem
			if err := rows.Scan(&item.ID, &item.Type, &item.Manufacturer,
			&item.Quantity, &item.StorageLocation, &item.RegistedAt); err != nil {
				log.Printf("list batteries: scan: %v", err)
				http.Error(w, "could not list batteries", http.StatusInternalServerError)
				return
			}
			batteries = append(batteries, item)
		}
		if err := rows.Err(); err != nil {
			log.Printf("list batteries: rows: %v", err)
			http.Error(w, "could not list batteries", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(batteries)
	}
}