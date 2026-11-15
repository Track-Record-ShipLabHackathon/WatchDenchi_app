# WatchDenchiのAPI契約メモ

以下は機能開発前の設計の正本です。入出力は意味を示しています。
JSON名、HTTPの詳細、モックの形式はFlutterとGoの担当者が合意した時点で更新します。
形式が確定したAPIからOpenAPIへ移す場合、移した契約はOpenAPIを正本にします。

| 画面 | 操作 | メソッド・パス | 入力 | 出力 |
| --- | --- | --- | --- | --- |
| ホーム画面 | 匿名認証 | `POST /api/client` | NULL | 認証トークン |
| ホーム画面 | 使用情報の管理ID取得 | `POST /api/device-battery` | NULL | 新規ID |
| ホーム画面 | 機器・電池の表示 | `GET /api/device-battery` | NULL | `status != inactive` のDEVICE_BATTERY。draftも含む |
| ホーム画面 | 残量の表示 | `GET /api/prediction` | NULL | DEVICE_BATTERYのIDごとの残量％ |
| バッテリー画面 | 登録済み電池の表示 | `GET /api/battery` | NULL | BATTERYの一覧 |
| バッテリー画面 | 使用バッテリー選択 | `PATCH /api/device-battery/{draft_id}` | 使用本数、付随情報の管理場所メモ・製造会社・種類 | NULL |
| バッテリー登録画面 | 在庫登録 | `POST /api/battery` | 電池の種類、製造会社（☆2の活用を想定）、管理本数、管理場所メモ | NULL |

ホーム画面の匿名認証は自動で1回を想定し、管理IDの取得は `draft_id == NULL` の場合に行います。
登録や選択のAPIはそのデータ操作を担当します。NAVIによる遷移はFlutterが行います。

## 契約を決めるときの確認事項

- NULLを空のボディ・JSONのnull・HTTP 204などのどれで表すか。JSONキー、型、単位、必須項目、入力検証、成功・エラー応答と認証トークンの送り方。
- 選択した `battery_id` の伝え方、登録したBATTERY.idを取得する方法、機器入力用API、GETの実行・再取得条件。
- 未選択の機器や電池を含むdraftをどう返し、残量を計算できないときに何を表示するか。保存成功時・通信失敗時のFlutter側の表示や遷移。
- 端末ごとの参照・更新範囲と、他の端末のIDを使った場合のエラー。

基盤が提供する運用APIは `GET /healthz`（HTTPサーバーの生存）と `GET /readyz`（DBへの接続確認）です。readyzは接続エラー時にHTTP 503を返します。上の7件のアプリ用APIは機能開発時に実装します。
