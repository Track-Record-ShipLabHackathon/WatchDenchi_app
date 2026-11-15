//go:build integration

package httpapi

import (
	"context"
	"database/sql"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestPostgresMigrationAndReadiness(t *testing.T) {
	databaseURL := os.Getenv("WATCHDENCHI_DATABASE_URL")
	if databaseURL == "" {
		t.Fatal("WATCHDENCHI_DATABASE_URL is required for the PostgreSQL test")
	}
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatal("could not configure PostgreSQL connection")
	}
	defer db.Close()

	response := httptest.NewRecorder()
	NewHandler(db.PingContext).ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("database readiness = %d, want %d", response.Code, http.StatusOK)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	var clientID int64
	if err := tx.QueryRowContext(ctx, "INSERT INTO client DEFAULT VALUES RETURNING id").Scan(&clientID); err != nil {
		t.Fatal(err)
	}
	var quantity int
	err = tx.QueryRowContext(ctx, "INSERT INTO battery (client_id, type, quantity) VALUES ($1, $2, $3) RETURNING quantity", clientID, "AA", 4).Scan(&quantity)
	if err != nil {
		t.Fatal(err)
	}
	if quantity != 4 {
		t.Errorf("stored battery quantity = %d, want 4", quantity)
	}
}
