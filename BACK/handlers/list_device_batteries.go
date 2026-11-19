package handlers

import (
	"context"
	"database/sql"
	"net/http"
	"time"
)

type usageItem struct {
	ID                         int64     `json:"id"`
	DeviceID                   int64     `json:"device_id"`
	DeviceType                 string    `json:"device_type"`
	DeviceName                 string    `json:"device_name"`
	BatteryID                  int64     `json:"battery_id"`
	BatteryType                string    `json:"battery_type"`
	Chemical                   *string   `json:"chemical"`
	Manufacturer               string    `json:"manufacturer"`
	BatteryQuantity            int32     `json:"battery_quantity"`
	StartedAt                  time.Time `json:"started_at"`
	PredictionAt               time.Time `json:"prediction_at"`
	RecommendedReplacementDate string    `json:"recommended_replacement_date"`
}

func ListDeviceBatteries(db *sql.DB) http.HandlerFunc {
	return withClient(db, func(w http.ResponseWriter, r *http.Request, ctx context.Context, clientID int64) error {
		rows, err := db.QueryContext(ctx, `SELECT u.id,u.device_id,d.type,d.name,u.battery_id,b.type,b.chemical,b.manufacturer,u.battery_quantity,u.started_at,u.prediction_at FROM device_battery u JOIN device d ON d.id=u.device_id JOIN battery b ON b.id=u.battery_id WHERE d.client_id=$1 AND b.client_id=$1 ORDER BY u.id`, clientID)
		if err != nil {
			return err
		}
		defer rows.Close()
		items := make([]usageItem, 0)
		for rows.Next() {
			var item usageItem
			if err := rows.Scan(&item.ID, &item.DeviceID, &item.DeviceType, &item.DeviceName, &item.BatteryID, &item.BatteryType, &item.Chemical, &item.Manufacturer, &item.BatteryQuantity, &item.StartedAt, &item.PredictionAt); err != nil {
				return err
			}
			item.RecommendedReplacementDate = item.PredictionAt.In(japanTime).Format("2006-01-02")
			items = append(items, item)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		return writeJSON(w, 200, items)
	})
}
