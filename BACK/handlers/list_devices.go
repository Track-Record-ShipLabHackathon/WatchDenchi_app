package handlers

import (
	"context"
	"database/sql"
	"net/http"
)

func ListDevices(db *sql.DB) http.HandlerFunc {
	return withClient(db, func(w http.ResponseWriter, r *http.Request, ctx context.Context, clientID int64) error {
		rows, err := db.QueryContext(ctx, `SELECT id,registered_at,type,name,client_id FROM device WHERE client_id=$1 ORDER BY id`, clientID)
		if err != nil {
			return err
		}
		defer rows.Close()
		items := make([]deviceItem, 0)
		for rows.Next() {
			var item deviceItem
			if err := rows.Scan(&item.ID, &item.RegisteredAt, &item.Type, &item.Name, &item.ClientID); err != nil {
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
