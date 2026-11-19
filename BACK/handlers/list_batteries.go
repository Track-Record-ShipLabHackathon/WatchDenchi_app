package handlers

import (
	"context"
	"database/sql"
	"net/http"
	"time"
)

type batteryListItem struct {
	ID              int64     `json:"id"`
	Type            string    `json:"type"`
	Chemical        *string   `json:"chemical"`
	Manufacturer    string    `json:"manufacturer"`
	Quantity        int32     `json:"quantity"`
	StorageLocation string    `json:"storage_location"`
	RegisteredAt    time.Time `json:"registered_at"`
}

func ListBatteries(db *sql.DB) http.HandlerFunc {
	return withClient(db, func(w http.ResponseWriter, r *http.Request, ctx context.Context, clientID int64) error {
		rows, err := db.QueryContext(ctx, `SELECT id,type,chemical,manufacturer,quantity,storage_location,registered_at FROM battery WHERE client_id=$1 ORDER BY id`, clientID)
		if err != nil {
			return err
		}
		defer rows.Close()
		items := make([]batteryListItem, 0)
		for rows.Next() {
			var item batteryListItem
			if err := rows.Scan(&item.ID, &item.Type, &item.Chemical, &item.Manufacturer, &item.Quantity, &item.StorageLocation, &item.RegisteredAt); err != nil {
				return err
			}
			items = append(items, item)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		return writeJSON(w, 200, items)
	})
}
