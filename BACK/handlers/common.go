package handlers

import (
 "context"
 "crypto/sha256"
 "database/sql"
 "encoding/json"
 "errors"
 "io"
 "log"
 "net/http"
 "strings"
 "time"
 "unicode/utf8"
)

type apiError struct { status int; code string; message string }
func (e *apiError) Error() string { return e.message }
func problem(status int, code, message string) error { return &apiError{status,code,message} }
type clientHandler func(http.ResponseWriter,*http.Request,context.Context,int64) error

func withClient(db *sql.DB, next clientHandler) http.HandlerFunc {
 return func(w http.ResponseWriter,r *http.Request) {
  w.Header().Set("Cache-Control","no-store")
  if db==nil { writeAPIError(w,problem(503,"database_unavailable","database unavailable"));return }
  auth:=strings.Fields(r.Header.Get("Authorization"))
  if len(auth)!=2 || !strings.EqualFold(auth[0],"Bearer") {writeUnauthorized(w);return}
  ctx,cancel:=context.WithTimeout(r.Context(),75*time.Second);defer cancel()
  tokenHash:=sha256.Sum256([]byte(auth[1]))
  var clientID int64
  err:=db.QueryRowContext(ctx,`SELECT id FROM client WHERE token_hash=$1`,tokenHash[:]).Scan(&clientID)
  if errors.Is(err,sql.ErrNoRows) {writeUnauthorized(w);return}
  if err==nil {err=next(w,r,ctx,clientID)}
  if err!=nil {writeAPIError(w,err)}
 }
}
func writeAPIError(w http.ResponseWriter,err error) {
 var failure *apiError
 if !errors.As(err,&failure) {log.Printf("API request failed: %v",err);failure=&apiError{500,"internal_error","could not complete request"}}
 w.Header().Set("Content-Type","application/json");w.Header().Set("Cache-Control","no-store");w.WriteHeader(failure.status)
 _=json.NewEncoder(w).Encode(map[string]any{"error":map[string]string{"code":failure.code,"message":failure.message}})
}
func writeUnauthorized(w http.ResponseWriter) {w.Header().Set("WWW-Authenticate","Bearer");writeAPIError(w,problem(401,"unauthorized","unauthorized"))}
func writeJSON(w http.ResponseWriter,status int,value any) error {
 w.Header().Set("Content-Type","application/json");w.WriteHeader(status);_=json.NewEncoder(w).Encode(value);return nil
}
func readJSON(w http.ResponseWriter,r *http.Request,target any) error {
 decoder:=json.NewDecoder(http.MaxBytesReader(w,r.Body,16*1024));decoder.DisallowUnknownFields()
 if err:=decoder.Decode(target);err!=nil {return problem(400,"invalid_json","a valid JSON object is required")}
 if err:=decoder.Decode(&struct{}{});err!=io.EOF {return problem(400,"invalid_json","send exactly one JSON object")}
 return nil
}
func validText(value string,max int) bool {return value!="" && utf8.RuneCountInString(value)<=max}
func notFound() error {return problem(404,"not_found","resource not found")}
var japanTime=time.FixedZone("JST",9*60*60)
