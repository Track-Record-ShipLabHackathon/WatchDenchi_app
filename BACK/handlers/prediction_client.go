package handlers

import (
 "bytes"
 "context"
 "encoding/json"
 "fmt"
 "io"
 "net/http"
 "net/url"
 "strings"
 "time"
)

type PredictionInput struct {
 StartedAt string `json:"started_at"`
 Type string `json:"type"`
 Chemical string `json:"chemical"`
 BatteryQuantity int32 `json:"battery_quantity"`
 Manufacturer string `json:"manufacturer"`
}
type Predictor interface { Predict(context.Context,PredictionInput)(time.Time,error) }
type HTTPPredictor struct { BaseURL string; Client *http.Client }
func NewHTTPPredictor(baseURL string)*HTTPPredictor {
 return &HTTPPredictor{BaseURL:strings.TrimRight(strings.TrimSpace(baseURL),"/"),Client:&http.Client{Timeout:60*time.Second}}
}
func(p *HTTPPredictor)Predict(ctx context.Context,input PredictionInput)(time.Time,error) {
 endpoint,err:=url.Parse(p.BaseURL)
 if err!=nil||endpoint.Host==""||(endpoint.Scheme!="http"&&endpoint.Scheme!="https")||endpoint.User!=nil||endpoint.RawQuery!=""||endpoint.Fragment!="" {
  return time.Time{},problem(503,"prediction_unavailable","WATCHDENCHI_INFERENCE_URL is not configured correctly")
 }
 payload,err:=json.Marshal(input);if err!=nil{return time.Time{},err}
 request,err:=http.NewRequestWithContext(ctx,http.MethodPost,p.BaseURL+"/predict",bytes.NewReader(payload))
 if err!=nil{return time.Time{},err};request.Header.Set("Content-Type","application/json")
 response,err:=p.Client.Do(request)
 if err!=nil{return time.Time{},problem(502,"prediction_unavailable","prediction service could not be reached; no changes were saved")}
 defer response.Body.Close()
 if response.StatusCode==422 {
  return time.Time{},problem(422,"unsupported_prediction","prediction supports only a mouse with alkaline AA x1, AAA x1 or AAA x2; check battery type, chemical and quantity")
 }
 if response.StatusCode!=200{return time.Time{},problem(502,"prediction_unavailable",fmt.Sprintf("prediction service returned HTTP %d; no changes were saved",response.StatusCode))}
 var result struct{Date string `json:"recommended_replacement_date"`}
 decoder:=json.NewDecoder(io.LimitReader(response.Body,1024*1024))
 if err:=decoder.Decode(&result);err!=nil{return time.Time{},problem(502,"invalid_prediction","prediction service returned invalid JSON")}
 if err:=decoder.Decode(&struct{}{});err!=io.EOF{return time.Time{},problem(502,"invalid_prediction","prediction service returned an invalid response")}
 predicted,err:=time.ParseInLocation("2006-01-02",result.Date,japanTime)
 if err!=nil{return time.Time{},problem(502,"invalid_prediction","prediction service returned an invalid date")}
 return predicted,nil
}
