# WatchDenchi

- Flutterは `apps/mobile`、Goは `services/api`、SQLは `db/migrations`、☆2のPython推論は `services/inference`。設計と暫定事項は `docs/design.md` と `contracts/README.md` を参照する。
- 使用情報の管理IDは `draft_id` を使う。未取得時はPOSTで取得し、入力順に関係なく同じIDをPATCHする。バッテリー情報フラグや、画面をまたぐ機器・電池の使用情報そのものの保持を追加しない。認証の `access_token` は別に保持する。
- FlutterのNAVIが画面を遷移させる。APIは入力・認証・保存・取得を担当し、遷移を指示しない。FlutterはGo APIを呼ぶ。設計上の7 APIと運用用 `/healthz`・`/readyz` を区別する。
- JSONキー、ステータスコード、認証、所有者、機器データ、物理式はチームの合意を記録してから機能として実装する。`status != inactive` はdraftを含む仕様として扱う。☆1はPythonの起動から独立させる。
- Go検証は `services/api` で `go vet ./...`、`go test -race ./...`（対応環境）、`go build ./...`。DB結合テストはローカル開発用DBへマイグレーション適用後に `go test -tags=integration ./internal/httpapi`。Flutter検証は `apps/mobile` で `flutter pub get --enforce-lockfile`、`flutter analyze --no-pub`、`flutter test --no-pub`。
- 作業ブランチとPRを使い、実施した検証を記載する。
