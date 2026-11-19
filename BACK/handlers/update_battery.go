package handlers

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
)

func UpdateBattery(db *sql.DB) http.HandlerFunc {
	return withClient(db, func(w http.ResponseWriter, r *http.Request, ctx context.Context, clientID int64) error {
		var input struct {
			ID       int64  `json:"id"`
			Quantity *int32 `json:"quantity"`
		}
		if err := readJSON(w, r, &input); err != nil {
			return err
		}
		if input.ID < 1 || input.Quantity == nil || *input.Quantity < 0 {
			return problem(400, "invalid_battery", "id and a nonnegative integer quantity are required")
		}
		var id int64
		err := db.QueryRowContext(ctx, `UPDATE battery SET quantity=$1 WHERE id=$2 AND client_id=$3 RETURNING id`, *input.Quantity, input.ID, clientID).Scan(&id)
		if errors.Is(err, sql.ErrNoRows) {
			return notFound()
		}
		if err != nil {
			return err
		}
		w.WriteHeader(http.StatusNoContent)
		return nil
	})
}
