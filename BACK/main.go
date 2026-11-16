package main

import (
	"log"
	"net/http"
	"github.com/Track-Record-ShipLabHackathon/WatchDenchi_app/BACK/health"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health.Liveness)

	const addr = "127.0.0.1:8080"
	log.Printf("WatchDenchi API starting on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
