# Flutter ⇄ Go 在庫API接続プロトタイプ

このブランチは、既存のWatchDenchi UIを変更せず、エレナの設計書の☆1のうち匿名認証・電池登録・在庫取得の接続を確認するための作業です。

## 現状
- `POST /api/client` → Goで匿名トークンを発行し、Flutterで復元する処理は既存実装です。
- `POST /api/battery` → Flutterの在庫登録操作から呼べる処理を今回追加しました。
- `GET /api/battery` → Flutterの在庫棚で取得・表示する処理を今回追加しました。
- *サーバー在庫モードは既定で無効*。ローカルの既存データを自動移行・削除しません。
- サーバー在庫モードでは在庫移動・使用・交換を停止します。Go側の PATCH や在庫更新APIがまだないためです。

## 実行例（テスト用）
```sh
cd FRONT
flutter pub get
flutter test test/watchdenchi_api_test.dart
flutter run -d chrome \
  --dart-define=WATCHDENCHI_API_BASE_URL=https://watchdenchi-app.onrender.com \
  --dart-define=WATCHDENCHI_ENABLE_SERVER_AUTH=true \
  --dart-define=WATCHDENCHI_ENABLE_SERVER_INVENTORY=true
```

**注意:** 在庫はサーバー側とローカル側で別管理です。試験モードを有効にしても、ローカルの過去データはDBに移行しません。既存データの上書き・同期は実装していません。接続できないときは通信エラーを表示し、誤って新規登録の再送を繰り返さないでください。

## 要確認（エレナと合意）
1. PostgreSQLの実際のテーブル名は `client` (既存Goと移行SQL) なのか `clients` (共有された新しい定義) なのか。両者は一致している必要があります。
2. Renderの `WATCHDENCHI_DATABASE_URL` とDB migrationが適用済みか。アカウント作成の実環境での動作は未検証です。
3. `battery` は `chemistry` 列をまだ持たないため、サーバー表示では「不明」とします。今後のカラム追加を決定する必要があります。
4. 保管場所変更・使用中・交換時の数量減少・機器の履歴は既存APIでは未対応。サーバー同期の本格導入前にDBとAPI設計を確定してください。
5. `SharedPreferences` の認証トークン保存はWebの強固な秘密保護を保証しません。公開本番の認証方式や失効・再登録フローは要検討です。

本ブランチをmainへマージしても、`WATCHDENCHI_ENABLE_SERVER_INVENTORY` を明示的に true にしない限り、既存の公開版在庫の動作は変わりません。
