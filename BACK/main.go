package main

import (
	"log"
	"net/http"
	"github.com/Track-Record-ShipLabHackathon/WatchDenchi_app/BACK/health"

	"os"

	"database/sql"
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/Track-Record-ShipLabHackathon/WatchDenchi_app/BACK/handlers"
)

func main() {
	var db *sql.DB
	databaseURL := os.Getenv("WATCHDENCHI_DATABASE_URL");
	if  (databaseURL != "") {
		var err error
		db, err = sql.Open("pgx", databaseURL)
		if (err != nil) {
			log.Fatal("could not initialize PostgreSQL from WATCHDENCHI_DATABASE_URL")
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health.Liveness)
	
	mux.HandleFunc("GET /readyz", health.Readiness(db))

	mux.HandleFunc("POST /api/client", handlers.CreateClient(db))

	mux.HandleFunc("POST /api/battery", handlers.RegisterBattery(db))

	port := os.Getenv("PORT");
	addr := "127.0.0.1:8080"
	if (port != "") {
		addr = "0.0.0.0:" + port
	}
	
	log.Printf("WatchDenchi API starting on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
