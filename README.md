# Watch-Denchi
Track Record @ ShipLab Hackathon

乾電池の在庫・保管場所・機器での使用状況・残量の目安を管理するアプリです。

| 場所 | 担当 |
| --- | --- |
| `apps/mobile/` | Flutterアプリ。既存の端末内保存の試作を収録 |
| `services/api/` | Go API、HTTPの起動とDB接続確認 |
| `db/migrations/` | PostgreSQLのスキーマ変更 |
| `services/inference/` | ☆2のPython推論サービス。☆1は起動不要 |
| `contracts/`、`docs/` | API、画面遷移・draft、配布の設計 |

## 必要なツール

Git、Go **1.27.4**、Flutter **3.50.0 stable**（同梱Dart **3.14.0**）、Docker Compose v2。
WindowsはDocker Desktopを起動し、WSLから作業する場合は、Docker Desktopの Settings → Resources → WSL Integration でUbuntuを有効にします。
Go・Flutterは起動するシェルから使える状態にします。DBはComposeの **PostgreSQL 17.12** を使います。
Pythonのセットアップは☆2の実装時に行います。
[Flutter SDKアーカイブ](https://docs.flutter.dev/install/archive) · [Goのリリース](https://go.dev/doc/devel/release) · [PostgreSQL 17.12のリリース](https://www.postgresql.org/about/news/postgresql-187-1712-1616-1520-1425-and-19-rc-2-released-3442/)

## ローカルで起動する

すでにクローンしているメンバーは、そのフォルダを開きます。新規参加者は作業用ディレクトリで一度だけ実行します。

```sh
git clone https://github.com/Track-Record-ShipLabHackathon/WatchDenchi_app.git
cd WatchDenchi_app
git status
go version
flutter --version
docker compose version
```

### 1. DBを起動し、マイグレーションを適用

Windows PowerShellは、Windows側のGo・Docker CLIを準備した状態で、リポジトリのルートから実行します。

```powershell
.\scripts\start-db.ps1
```

WSLの既存クローンでは、PowerShellから `wsl -d Ubuntu` を実行し、Ubuntuのシェルでクローン先に移動します。

```bash
[ -f .env ] || cp .env.example .env
docker compose up -d --wait db
for migration in db/migrations/*.sql; do
  docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U watchdenchi -d watchdenchi < "$migration" || break
done
```

`.env.example` はローカル専用の値です。`.env` はGit管理外です。
DBは既定でホストの `127.0.0.1:15432` で待機します。ポートを変えたら `.env` の `WATCHDENCHI_DB_PORT` と接続URLを両方更新します。
開発環境を停止するにはリポジトリのルートで `docker compose stop` を実行します。データは名前付きボリュームに保存されます。

### 2. Go APIを起動

PowerShellはリポジトリのルートで以下を実行します。

```powershell
.\scripts\start-api.ps1
```

WSL・Linuxはリポジトリのルートで以下を実行します。Goをインストール済みのWSLで `go` が見つからなければ、`export PATH=/usr/local/go/bin:$PATH` で確認します。

```bash
set -a
. ./.env
set +a
cd services/api
go run ./cmd/api
```

別のターミナルで確認します。Windowsでは `curl` を `curl.exe` として実行できます。

```sh
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/readyz
```

両方がHTTP 200なら、HTTPサーバーの起動とDB疎通を確認できています。`readyz` が503の場合はDBの状態と接続URLを確認してください。

### 3. Flutterを起動

Flutter SDKと実行対象を使えるターミナルで、リポジトリのルートから実行します。WindowsのFlutterを使う場合、Windows側からソースを開ける必要があります。

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
flutter devices
flutter run -d chrome --dart-define=WATCHDENCHI_API_BASE_URL=http://127.0.0.1:8080
```

| 実行する場所 | API接続先の指定例 |
| --- | --- |
| APIと同じPCのChromeやデスクトップ | `http://127.0.0.1:8080`。GoをWSLで動かしブラウザをWindowsで開く場合は、Windows側からも疎通を確認 |
| Android標準エミュレーター | `http://10.0.2.2:8080`。Flutterの `-d` には `flutter devices` の端末IDを指定 |
| 実機 | 同じネットワークにあるAPIホストのLANアドレス。HTTPを使う場合は端末側の開発用設定と、Goの待ち受け・ファイアウォールを確認 |

接続先は `--dart-define` で変えられます。Flutterの試作データは端末内に保存されます。
機能APIを接続する段階で、ブラウザーの同一オリジンまたは開発用CORS、Android/iOSのHTTP制約を実機で確認します。公開時はHTTPSを使います。
`--dart-define` に入れるのは公開可能な接続先です。秘密鍵やサービスの認証情報はサーバー側で管理します。

## チームでの開発手順

1. 作業前にリポジトリのルートで `git switch main` と `git pull --ff-only origin main` を実行。
2. Issueに目的・完了条件・依存関係を記入し、`git switch -c feature/機能名` でブランチを作成。
3. 担当範囲のチェックを実行し、`git add 変更ファイル`、`git commit -m "変更内容"`。
4. `git push -u origin feature/機能名` を実行し、GitHubで `main` に向けたPRを作成。確認方法と判断理由を残し、CIとレビューを確認してから統合。

クローン時のHTTPSでpushできず、SSH認証を設定済みなら、送信時だけ `git -c remote.origin.pushurl=git@github.com:Track-Record-ShipLabHackathon/WatchDenchi_app.git push -u origin HEAD` と指定できます。

依存を変更する場合は、その変更と `go.mod`・`go.sum` または `pubspec.yaml`・`pubspec.lock` の差分を同じPRに含めます。

| 確認 | 実行ディレクトリとコマンド |
| --- | --- |
| Go | `services/api` で `gofmt -l .`、`go vet ./...`、`go test -race ./...`、`go build ./...`。race検出には対応環境とCコンパイラーが必要 |
| DB | マイグレーション適用済みの開発DBへ、`WATCHDENCHI_DATABASE_URL` を設定したシェルの `services/api` で `go test -race -tags=integration ./...` |
| Flutter | `apps/mobile` で `flutter pub get --enforce-lockfile`、`dart format --output=none --set-exit-if-changed lib test`、`flutter analyze --no-pub`、`flutter test --no-pub` |

[画面・データ設計](docs/design.md) · [API契約メモ](contracts/README.md) · [GitHubと配布](docs/delivery.md)
