package handlers

import (
	"context"
	"database/sql"
	"net/http"
	"strings"
	"unicode/utf8"
)

func RegisterBattery(db *sql.DB) http.HandlerFunc {
	return withClient(db, func(w http.ResponseWriter, r *http.Request, ctx context.Context, clientID int64) error {
		var input struct {
			Type            string `json:"type"`
			Chemical        string `json:"chemical"`
			Manufacturer    string `json:"manufacturer"`
			Quantity        int32  `json:"quantity"`
			StorageLocation string `json:"storage_location"`
		}
		if err := readJSON(w, r, &input); err != nil {
			return err
		}
		input.Type = strings.TrimSpace(input.Type)
		input.Chemical = strings.TrimSpace(input.Chemical)
		input.Manufacturer = strings.TrimSpace(input.Manufacturer)
		input.StorageLocation = strings.TrimSpace(input.StorageLocation)
		if !validText(input.Type, 30) || !validText(input.Chemical, 30) || !validText(input.Manufacturer, 100) || input.Quantity < 1 || utf8.RuneCountInString(input.StorageLocation) > 200 {
			return problem(400, "invalid_battery", "type, chemical, manufacturer and a positive integer quantity are required")
		}
		_, err := db.ExecContext(ctx, `INSERT INTO battery (client_id,type,chemical,manufacturer,quantity,storage_location) VALUES ($1,$2,$3,$4,$5,$6)`, clientID, input.Type, input.Chemical, input.Manufacturer, input.Quantity, input.StorageLocation)
		if err != nil {
			return err
		}
		w.WriteHeader(http.StatusCreated)
		return nil
	})
}
