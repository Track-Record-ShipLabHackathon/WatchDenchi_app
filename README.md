# Watch-Denchi_app

- **☆1**：Version.01
- **☆2**：Version.02（時間に余裕があれば追加する）

## アプリケーションアーキテクチャ

システム設計録：https://battery-design-explorer.tweedygrape8.chatgpt.site

Watch-Denchi_appは、Flutter・Go・PostgreSQLの３層アーキテクチャで構成される。

- **Flutter**：プレゼンテーション層
- **Go**：アプリケーション層（API Server）
- **PostgreSQL**：データベース層

```mermaid
flowchart TB
    Flutter["<strong>Flutter</strong><br/>Web：GitHub Pages<br/>Android：APK"]
    Go["<strong>Go</strong><br/>Render Web Service"]
    DB["<strong>PostgreSQL</strong><br/>Render Postgres"]
    Python["Python（☆2）<br/>推論SOA<br/>"]

    Flutter <-->|API| Go
    Go <-->|PGX| DB
    Go <-->|API| Python

    classDef frontend fill:#192b45,stroke:#4c89de,color:#fff
    classDef backend fill:#36301e,stroke:#e2ba50,color:#fff
    classDef database fill:#392733,stroke:#dc83b2,color:#fff
    classDef inference fill:#1e3534,stroke:#53bdb6,color:#fff

    class Flutter frontend
    class Go backend
    class DB database
    class Python inference
```

## フォルダ構成

以下は☆1の構成です。☆2は、時間に余裕があれば追加します。

```text
WatchDenchi_app/
├── FRONT/                              ー Flutter（プレゼンテーション層）
│   ├── ・・・         
├── BACK/                               ー Go（アプリケーション層）
│   ├── go.mod                          
│   ├── go.sum                          
│   ├── main.go                         ーー HTTP Server
│   ├── handlers/                       ーー Fultter向けAPI
│   │   ├── create_client.go                ☆1：POST  /api/client
│   │   ├── create_device_battery.go        ☆1：POST  /api/device-battery
│   │   ├── list_device_batteries.go        ☆1：GET   /api/device-battery
│   │   ├── list_predictions.go             ☆2：GET   /api/prediction
│   │   ├── list_batteries.go               ☆1：GET   /api/battery
│   │   ├── select_battery.go               ☆1：PATCH /api/device-battery/{draft_id}
│   │   └── register_battery.go             ☆1：POST  /api/battery
│   └── health/                         ーー CICD向けAPI
│       ├── liveness.go                          GET /healthz
│       ├── liveness_test.go            
│       ├── readiness.go                         GET /readyz
│       └── readiness_test.go           
├── DB/                                 ー PostgreSQL（データベース層）
├── inference/                          ー Python（☆2：推論SOA）
├── docs/                               
├── .github/workflows/                  ー CICD設定
│   ├── flutter.yml                     
│   └── go.yml                          
├── .env.example                        
├── .gitignore                          
├── compose.yaml                        
└── README.md                           
```

- **CI**：`flutter.yml` は `FRONT/` でFlutterの静的解析・テストを実行します。`go.yml` は `BACK/` でGoのテスト・ビルドを実行し、`DB/` のSQLを使ってPostgreSQLとの接続も検証します。
- **CD**：

## API仕様と反映手順

- [主要APIの仕様](docs/api.md)
- [DB変更・Goのデプロイ手順](docs/device-api-deploy.md)
- [Flutter担当者向けの接続指示](docs/flutter-integration.md)
