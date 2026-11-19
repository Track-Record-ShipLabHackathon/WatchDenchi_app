// Explicit migration command. Starting the API never changes the DB schema.
package main

import (
 "context"
 "database/sql"
 "fmt"
 "log"
 "os"
 "path/filepath"
 "strings"
 "time"
 _ "github.com/jackc/pgx/v5/stdlib"
)

func main(){
 if len(os.Args)!=2{log.Fatal("usage: go run ./cmd/migrate ../DB/0003_device_prediction.sql")}
 path:=os.Args[1]
 if filepath.Base(path)!="0003_device_prediction.sql"{log.Fatal("this command only applies 0003_device_prediction.sql")}
 migration,err:=os.ReadFile(path);if err!=nil{log.Fatal(err)}
 databaseURL:=os.Getenv("WATCHDENCHI_DATABASE_URL");if databaseURL==""{log.Fatal("WATCHDENCHI_DATABASE_URL is required")}
 db,err:=sql.Open("pgx",databaseURL);if err!=nil{log.Fatal("could not initialize database")};defer db.Close()
 ctx,cancel:=context.WithTimeout(context.Background(),30*time.Second);defer cancel()
 // The SQL file carries BEGIN/COMMIT. Use one dedicated connection.
 conn,err:=db.Conn(ctx);if err!=nil{log.Fatal("could not connect to database")};defer conn.Close()
 if _,err:=conn.ExecContext(ctx,"SELECT pg_advisory_lock(88190119)");err!=nil{log.Fatal("could not lock migration")}
 defer conn.ExecContext(context.Background(),"SELECT pg_advisory_unlock(88190119)")
 var applied bool
 err=conn.QueryRowContext(ctx,`SELECT
 EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='battery' AND column_name='registered_at')
 AND EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='battery' AND column_name='chemical')
 AND to_regclass('device') IS NOT NULL AND to_regclass('device_battery') IS NOT NULL`).Scan(&applied)
 if err!=nil{log.Fatal("could not inspect database")}
 if applied{fmt.Println("0003 is already applied; nothing changed");return}
 if !strings.HasPrefix(strings.TrimSpace(string(migration)),"BEGIN;"){log.Fatal("migration must use a transaction")}
 if _,err:=conn.ExecContext(ctx,string(migration));err!=nil{log.Fatalf("migration failed (transaction not committed): %v",err)}
 fmt.Println("0003 applied successfully")
}
