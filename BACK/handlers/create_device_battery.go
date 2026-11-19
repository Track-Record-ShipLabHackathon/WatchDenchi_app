package handlers

import (
 "context"
 "database/sql"
 "errors"
 "net/http"
 "time"
)

type batteryForPrediction struct {
 ID int64
 Type string
 Chemical sql.NullString
 Manufacturer string
 Quantity int32
}
func selectedBattery(ctx context.Context,db *sql.DB,clientID,batteryID int64)(batteryForPrediction,error) {
 var battery batteryForPrediction
 err:=db.QueryRowContext(ctx,`SELECT id,type,chemical,manufacturer,quantity FROM battery WHERE id=$1 AND client_id=$2`,batteryID,clientID).
  Scan(&battery.ID,&battery.Type,&battery.Chemical,&battery.Manufacturer,&battery.Quantity)
 if errors.Is(err,sql.ErrNoRows){return battery,notFound()};return battery,err
}
func requestPrediction(ctx context.Context,predictor Predictor,battery batteryForPrediction,quantity int32,started time.Time)(time.Time,error) {
 if !battery.Chemical.Valid||battery.Chemical.String==""{return time.Time{},problem(422,"chemical_required","this battery has no chemical information; register a battery with its actual chemical")}
 if predictor==nil{return time.Time{},problem(503,"prediction_unavailable","prediction service is not configured")}
 return predictor.Predict(ctx,PredictionInput{StartedAt:started.Format(time.RFC3339Nano),Type:battery.Type,Chemical:battery.Chemical.String,BatteryQuantity:quantity,Manufacturer:battery.Manufacturer})
}
func consumeStock(ctx context.Context,tx *sql.Tx,clientID,batteryID int64,quantity int32)error {
 result,err:=tx.ExecContext(ctx,`UPDATE battery SET quantity=quantity-$1 WHERE id=$2 AND client_id=$3 AND quantity >= $1`,quantity,batteryID,clientID)
 if err!=nil{return err};count,err:=result.RowsAffected();if err!=nil{return err}
 if count!=1{return problem(409,"insufficient_stock","not enough unused batteries; no changes were saved")}
 return nil
}

func CreateDeviceBattery(db *sql.DB,predictor Predictor)http.HandlerFunc {
 return withClient(db,func(w http.ResponseWriter,r *http.Request,ctx context.Context,clientID int64)error {
  var input struct{DeviceID int64 `json:"device_id"`;BatteryID int64 `json:"battery_id"`;Quantity int32 `json:"battery_quantity"`}
  if err:=readJSON(w,r,&input);err!=nil{return err}
  if input.DeviceID<1||input.BatteryID<1||input.Quantity<1||input.Quantity>100{return problem(400,"invalid_installation","positive device_id, battery_id and battery_quantity (1-100) are required")}
  var deviceType string
  err:=db.QueryRowContext(ctx,`SELECT type FROM device WHERE id=$1 AND client_id=$2`,input.DeviceID,clientID).Scan(&deviceType)
  if errors.Is(err,sql.ErrNoRows){return notFound()};if err!=nil{return err}
  if !isMouse(deviceType){return problem(422,"unsupported_device","prediction currently supports only a mouse")}
  battery,err:=selectedBattery(ctx,db,clientID,input.BatteryID);if err!=nil{return err}
  if battery.Quantity<input.Quantity{return problem(409,"insufficient_stock","not enough unused batteries")}
  var exists bool
  if err:=db.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM device_battery WHERE device_id=$1)`,input.DeviceID).Scan(&exists);err!=nil{return err}
  if exists{return problem(409,"already_installed","this device already has batteries")}
  started:=time.Now().UTC()
  predicted,err:=requestPrediction(ctx,predictor,battery,input.Quantity,started);if err!=nil{return err}

  tx,err:=db.BeginTx(ctx,nil);if err!=nil{return err};defer tx.Rollback()
  // A device row lock serializes competing initial installations.
  var deviceID int64
  err=tx.QueryRowContext(ctx,`SELECT id FROM device WHERE id=$1 AND client_id=$2 FOR UPDATE`,input.DeviceID,clientID).Scan(&deviceID)
  if errors.Is(err,sql.ErrNoRows){return notFound()};if err!=nil{return err}
  if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM device_battery WHERE device_id=$1)`,deviceID).Scan(&exists);err!=nil{return err}
  if exists{return problem(409,"already_installed","this device already has batteries")}
  if err:=consumeStock(ctx,tx,clientID,input.BatteryID,input.Quantity);err!=nil{return err}
  _,err=tx.ExecContext(ctx,`INSERT INTO device_battery (device_id,battery_id,battery_quantity,started_at,prediction_at) VALUES ($1,$2,$3,$4,$5)`,deviceID,input.BatteryID,input.Quantity,started,predicted)
  if err!=nil{return err};if err:=tx.Commit();err!=nil{return err}
  w.WriteHeader(http.StatusCreated);return nil
 })
}
