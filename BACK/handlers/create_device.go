package handlers
import ("context";"database/sql";"net/http";"strings";"time")
type deviceItem struct {
 ID int64 `json:"id"`
 RegisteredAt time.Time `json:"registered_at"`
 Type string `json:"type"`
 Name string `json:"name"`
 ClientID int64 `json:"client_id"`
}
func CreateDevice(db *sql.DB) http.HandlerFunc {
 return withClient(db,func(w http.ResponseWriter,r *http.Request,ctx context.Context,clientID int64) error {
  var input struct{Type string `json:"type"`;Name string `json:"name"`}
  if err:=readJSON(w,r,&input);err!=nil{return err}
  input.Type,input.Name=strings.TrimSpace(input.Type),strings.TrimSpace(input.Name)
  if !validText(input.Type,30)||!validText(input.Name,100){return problem(400,"invalid_device","type and name are required")}
  var item deviceItem
  err:=db.QueryRowContext(ctx,`INSERT INTO device (type,name,client_id) VALUES ($1,$2,$3) RETURNING id,registered_at,type,name,client_id`,input.Type,input.Name,clientID).Scan(&item.ID,&item.RegisteredAt,&item.Type,&item.Name,&item.ClientID)
  if err!=nil{return err};return writeJSON(w,http.StatusCreated,item)
 })
}
func isMouse(value string)bool {value=strings.ToLower(strings.TrimSpace(value));return value=="mouse"||value=="マウス"}
