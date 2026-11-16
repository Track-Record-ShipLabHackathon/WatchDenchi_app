package main

import (
	"log"
	"net/http"
	"github.com/Track-Record-ShipLabHackathon/WatchDenchi_app/BACK/health"

	"os"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health.Liveness)

	port := os.Getenv("PORT");
	addr := "127.0.0.1:8080"
	if (port != "") {
		addr = "0.0.0.0:" + port
	}
	
	log.Printf("WatchDenchi API starting on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
