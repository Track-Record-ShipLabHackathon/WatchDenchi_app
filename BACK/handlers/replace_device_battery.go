package handlers

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"time"
)

type usageSnapshot struct {
	BatteryID  int64
	Quantity   int32
	StartedAt  time.Time
	DeviceType string
}

func ReplaceDeviceBattery(db *sql.DB, predictor Predictor) http.HandlerFunc {
	return withClient(db, func(w http.ResponseWriter, r *http.Request, ctx context.Context, clientID int64) error {
		var input struct {
			ID        int64 `json:"id"`
			BatteryID int64 `json:"battery_id"`
		}
		if err := readJSON(w, r, &input); err != nil {
			return err
		}
		if input.ID < 1 || input.BatteryID < 1 {
			return problem(400, "invalid_replacement", "positive id and battery_id are required")
		}
		var snapshot usageSnapshot
		err := db.QueryRowContext(ctx, `SELECT u.battery_id,u.battery_quantity,u.started_at,d.type FROM device_battery u JOIN device d ON d.id=u.device_id WHERE u.id=$1 AND d.client_id=$2`, input.ID, clientID).
			Scan(&snapshot.BatteryID, &snapshot.Quantity, &snapshot.StartedAt, &snapshot.DeviceType)
		if errors.Is(err, sql.ErrNoRows) {
			return notFound()
		}
		if err != nil {
			return err
		}
		if !isMouse(snapshot.DeviceType) {
			return problem(422, "unsupported_device", "prediction currently supports only a mouse")
		}
		battery, err := selectedBattery(ctx, db, clientID, input.BatteryID)
		if err != nil {
			return err
		}
		if battery.Quantity < snapshot.Quantity {
			return problem(409, "insufficient_stock", "not enough unused batteries")
		}
		started := time.Now().UTC()
		predicted, err := requestPrediction(ctx, predictor, battery, snapshot.Quantity, started)
		if err != nil {
			return err
		}

		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		defer tx.Rollback()
		var current usageSnapshot
		err = tx.QueryRowContext(ctx, `SELECT u.battery_id,u.battery_quantity,u.started_at FROM device_battery u JOIN device d ON d.id=u.device_id WHERE u.id=$1 AND d.client_id=$2 FOR UPDATE OF u`, input.ID, clientID).
			Scan(&current.BatteryID, &current.Quantity, &current.StartedAt)
		if errors.Is(err, sql.ErrNoRows) {
			return notFound()
		}
		if err != nil {
			return err
		}
		// If another exchange finished while inference was running, do not consume twice.
		if current.BatteryID != snapshot.BatteryID || current.Quantity != snapshot.Quantity || !current.StartedAt.Equal(snapshot.StartedAt) {
			return problem(409, "usage_changed", "this device changed during prediction; reload its current state")
		}
		if err := consumeStock(ctx, tx, clientID, input.BatteryID, current.Quantity); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE device_battery SET battery_id=$1,started_at=$2,prediction_at=$3 WHERE id=$4`, input.BatteryID, started, predicted, input.ID)
		if err != nil {
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
		w.WriteHeader(http.StatusNoContent)
		return nil
	})
}
