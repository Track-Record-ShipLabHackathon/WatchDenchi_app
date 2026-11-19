package handlers
import ("context";"database/sql";"errors";"net/http";"strconv";"time")
func ListPredictions(db *sql.DB)http.HandlerFunc {
 return withClient(db,func(w http.ResponseWriter,r *http.Request,ctx context.Context,clientID int64)error {
  values,ok:=r.URL.Query()["device_battery_id"]
  if !ok||len(values)!=1{return problem(400,"invalid_id","device_battery_id is required")}
  id,err:=strconv.ParseInt(values[0],10,64);if err!=nil||id<1{return problem(400,"invalid_id","device_battery_id must be a positive integer")}
  var predicted time.Time
  err=db.QueryRowContext(ctx,`SELECT u.prediction_at FROM device_battery u JOIN device d ON d.id=u.device_id JOIN battery b ON b.id=u.battery_id WHERE u.id=$1 AND d.client_id=$2 AND b.client_id=$2`,id,clientID).Scan(&predicted)
  if errors.Is(err,sql.ErrNoRows){return notFound()};if err!=nil{return err}
  return writeJSON(w,200,map[string]any{"device_battery_id":id,"recommended_replacement_date":predicted.In(japanTime).Format("2006-01-02")})
 })
}
