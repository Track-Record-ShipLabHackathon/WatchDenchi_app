# DBとGo APIの反映手順

## 実装済みの範囲

電池のchemical・registered_at、在庫数更新、機器登録・一覧、初回装着・交換・使用中一覧、Python予測と保存済み予測日の取得です。

Pythonの接続先は https://watchdenchi-inference.onrender.com です。
Goサービスに WATCHDENCHI_INFERENCE_URL を設定してください。

## DBの扱い

0001と0002は既存DBに適用済みの履歴として残します。新しい0003だけを既存DBへ適用します。0003は列名を変更してテーブルを追加します。データの削除やDBの作り直しはしません。

古い電池のchemicalはNULLです。アルカリなどを推測して補完しません。予測のデモではchemicalを指定した新しい電池を登録できます。

SQLファイルをGitHubに置くこと、Goサービスの再起動、PostgreSQLの再起動ではSQLは自動適用されません。

## 反映する順番

1. PRのGo CI成功と変更内容を確認する。
2. RenderのGoサービスのAuto-Deployを一時Offにする。
3. 以下の手順で0003を適用する。
4. PRをmainへマージする。
5. RenderのGoサービスでManual Deploy → Deploy latest commitを実行する。
6. 公開APIのスモークテストを行う。
7. 正常を確認して、Auto-DeployをAfter CI Checks Passに戻す。

0003で列名が変わった後は、旧Goの在庫一覧が使えなくなります。DB適用後は続けて新Goをデプロイしてください。Restart serviceは古いコードの再起動なので、Deploy latest commitを使います。

## ローカルにブランチを取得する

Ubuntuで、未コミットの変更がないことを確認します。

```bash
cd ~/WatchDenchi_app
git status --short
git fetch origin
git switch --track -c feature/device-battery-api origin/feature/device-battery-api
```

同名のローカルブランチが既にあれば、作成の代わりに git switch feature/device-battery-api を使います。

## 既存のRender DBへ0003を適用する

ローカルのGoを使います。psqlの追加インストールは不要です。URLにはRender PostgreSQLのExternal Database URLを使い、チャットやGitに貼り付けません。

```bash
cd ~/WatchDenchi_app/BACK
(
  read -rsp 'RenderのExternal Database URL: ' WATCHDENCHI_DATABASE_URL || exit 1
  printf '\n'
  export WATCHDENCHI_DATABASE_URL
  go run ./cmd/migrate ../DB/0003_device_prediction.sql
)
```

成功時は 0003 applied successfully と出ます。適用済みの構造がそろっていれば0003 is already applied; nothing changedと表示します。
失敗したら先にエラーを確認し、0001/0002の再実行やDB削除はしません。

cmd/migrateは専用の接続で明示的に0003を実行します。API起動時にDBを書き換える構成ではありません。

## 公開後の確認

UbuntuのPython 3.10.12で使える標準ライブラリだけのスクリプトです。

```bash
cd ~/WatchDenchi_app
python3 scripts/smoke-device-api.py https://watchdenchi-app.onrender.com
```

専用の匿名利用者とテスト用在庫・機器を新規作成し、登録→装着→予測取得→交換→利用者分離を確認します。作成した少量のテストデータはDBに残ります。トークンは表示しません。

API source/DB反映だけでは既存Flutter画面はサーバー保存に切り替わりません。Flutter担当者には [flutter-integration.md](flutter-integration.md) を共有してください。

## CIでの検証

Go CIではPostgreSQL 17の一時DB watchdenchi_test に0001→0002→0003を適用し、go build ./... と go test -race -count=1 -v ./... を実行します。本番DBのURLやデータは使いません。テスト時だけGitHub Actions内にPostgreSQLコンテナが作られ、アプリの公開にDockerを導入する必要はありません。
