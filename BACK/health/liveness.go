package health

import (
	"fmt"
	"net/http"
)

func Liveness(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintln(w, `{"status": "ok"}`)
}