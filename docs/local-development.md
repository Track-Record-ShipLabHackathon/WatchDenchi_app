# ローカルのFlutter WebからGo APIへ接続する

GitHub PagesのOriginは常に許可します。開発用のOriginはGo側の環境変数で切り替えます。

- WATCHDENCHI_ALLOW_LOCALHOST_CORS=true: http://localhost と http://127.0.0.1 を任意の有効なポートで許可します。
- 未設定・false: GitHub Pagesだけを許可します。
- LAN内の別IP、別ホスト、HTTPSのlocalhost、IPv6のループバックはこの設定の対象外です。

## RenderのAPIに接続する場合

1. この修正をmainにマージし、RenderのGo Web Service「watchdenchi-app」に新しいコードをデプロイします。
2. 同じGo Web ServiceのEnvironmentで次を追加し、変更を反映します。

```text
WATCHDENCHI_ALLOW_LOCALHOST_CORS=true
```

設定する場所はFlutter側やPostgreSQLではなく、リクエストを受け取るGo側です。
環境変数だけを追加しても、旧コードでは有効になりません。
ローカル開発を終えて許可が不要になったら削除するかfalseに戻します。

## ローカルのGoに接続する場合

Ubuntu/bashではBACKディレクトリから次を実行します。
既存のDB接続・予測サービス接続の環境変数は別途設定済みであることを前提とします。

```bash
cd ~/WatchDenchi_app/BACK
WATCHDENCHI_ALLOW_LOCALHOST_CORS=true go run .
```

## CORSの確認

次のリクエストはDBの登録や更新を行いません。

```bash
curl -i -X OPTIONS \
  https://watchdenchi-app.onrender.com/api/client \
  -H 'Origin: http://localhost:54332' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type'
```

期待する応答:

```text
HTTP/2 204
Access-Control-Allow-Origin: http://localhost:54332
Access-Control-Allow-Methods: GET, POST, PATCH
Access-Control-Allow-Headers: Authorization, Content-Type
Vary: Origin
```

実際のFlutter開発ポートが異なる場合も、同じ設定で許可します。
Bearerトークンを使うAPIではAuthorizationヘッダーも引き続き必要です。
CORSの成功はDB接続や認証の成功を保証しないため、プリフライトの後に実際の画面操作を確認します。

## CI

PRでGoの整形、ビルド、テストを実行します。
CORSのテストでは、既存のGitHub Pages、開発設定のON/OFF、可変ポート、
紛らわしいホスト名や不正なOriginの拒否、認証ヘッダーとエラー応答を検証します。
