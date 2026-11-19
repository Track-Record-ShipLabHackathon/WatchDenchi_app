package main

import (
	"database/sql"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/Track-Record-ShipLabHackathon/WatchDenchi_app/BACK/handlers"
	"github.com/Track-Record-ShipLabHackathon/WatchDenchi_app/BACK/health"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func newRouter(db *sql.DB, predictor handlers.Predictor) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health.Liveness)
	mux.HandleFunc("GET /readyz", health.Readiness(db))
	mux.HandleFunc("POST /api/client", handlers.CreateClient(db))
	mux.HandleFunc("POST /api/battery", handlers.RegisterBattery(db))
	mux.HandleFunc("GET /api/battery", handlers.ListBatteries(db))
	mux.HandleFunc("PATCH /api/battery", handlers.UpdateBattery(db))
	mux.HandleFunc("POST /api/device", handlers.CreateDevice(db))
	mux.HandleFunc("GET /api/device", handlers.ListDevices(db))
	mux.HandleFunc("POST /api/device-battery", handlers.CreateDeviceBattery(db, predictor))
	mux.HandleFunc("GET /api/device-battery", handlers.ListDeviceBatteries(db))
	mux.HandleFunc("PATCH /api/device-battery", handlers.ReplaceDeviceBattery(db, predictor))
	mux.HandleFunc("GET /api/prediction", handlers.ListPredictions(db))
	return withCORS(mux)
}
func main() {
	var db *sql.DB
	if databaseURL := os.Getenv("WATCHDENCHI_DATABASE_URL"); databaseURL != "" {
		var err error
		db, err = sql.Open("pgx", databaseURL)
		if err != nil {
			log.Fatal("could not initialize PostgreSQL from WATCHDENCHI_DATABASE_URL")
		}
		defer db.Close()
		db.SetMaxOpenConns(5)
		db.SetMaxIdleConns(2)
		db.SetConnMaxLifetime(30 * time.Minute)
	}
	addr := "127.0.0.1:8080"
	if port := os.Getenv("PORT"); port != "" {
		addr = "0.0.0.0:" + port
	}
	server := &http.Server{Addr: addr, Handler: newRouter(db, handlers.NewHTTPPredictor(os.Getenv("WATCHDENCHI_INFERENCE_URL"))), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 90 * time.Second, IdleTimeout: 60 * time.Second}
	log.Printf("WatchDenchi API starting on %s", addr)
	log.Fatal(server.ListenAndServe())
}
