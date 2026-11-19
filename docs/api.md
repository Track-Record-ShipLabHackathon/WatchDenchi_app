# WatchDenchi API仕様

Goの公開URL: https://watchdenchi-app.onrender.com
PythonはGoから呼び出します。FlutterからはGoへ接続します。

## 認証と共通仕様

- 初回だけ POST /api/client を呼び、返された access_token を既存の匿名セッション保存処理で保持します。
- それ以外の /api/* には Authorization: Bearer <access_token> を付けます。
- client_id はGoがトークンから決めます。Flutterの入力値として送る必要はありません。
- GET /api/client は実装していません。保存済みトークンの再利用に必須ではありません。
- 新規トークンを作り直すと別利用者になります。通信障害や502だけで保存済みトークンを消さないでください。
- JSONは Content-Type: application/json、項目名はsnake_caseです。
- 他人の電池・機器・使用中情報を指定した場合は404です。
- 成功本文が空の201/204に jsonDecode を適用しないでください。
- 一覧はJSON配列です。空の一覧は [] です。

| メソッド | パス | 成功 |
| --- | --- | --- |
| POST | /api/client | 201、access_token |
| POST | /api/battery | 201、空本文 |
| GET | /api/battery | 200、電池一覧 |
| PATCH | /api/battery | 204、空本文 |
| POST | /api/device | 201、登録済み機器 |
| GET | /api/device | 200、機器一覧 |
| POST | /api/device-battery | 201、空本文 |
| GET | /api/device-battery | 200、使用中情報一覧 |
| PATCH | /api/device-battery | 204、空本文 |
| GET | /api/prediction?device_battery_id=30 | 200、保存済み交換推奨日 |

## 電池

POST /api/battery の入力例:

```json
{"type":"単3形","chemical":"アルカリ","manufacturer":"テスト","quantity":5,"storage_location":"机の棚"}
```

type・chemicalは空でない30文字以内、manufacturerは空でない100文字以内、quantityは1以上の整数です。storage_locationは空文字も使用可能で200文字以内です。新しい在庫レコードを作ります。同じ属性の電池でもIDは別です。

GET /api/battery の応答例:

```json
[{"id":20,"type":"単3形","chemical":"アルカリ","manufacturer":"テスト","quantity":5,"storage_location":"机の棚","registered_at":"2026-11-19T01:00:00Z"}]
```

登録日時は registered_at です。旧 registed_at は返しません。既存データの化学系は推測せず chemical: null のまま残します。化学系が不明の電池は予測付き装着に使用できません。

PATCH /api/battery の入力例:

```json
{"id":20,"quantity":3}
```

quantityは変更後の未使用在庫数です。差分ではありません。0以上の整数を指定します。このAPIでは保管場所の変更・分割は扱いません。

## 機器登録

POST /api/device:

```json
{"type":"マウス","name":"机のマウス"}
```

typeは機器の種類です。電池の単3・単4ではありません。nameは機器の登録名です。typeは30文字以内、nameは100文字以内の空でない文字列です。

応答例:

```json
{"id":10,"registered_at":"2026-11-19T01:00:00Z","type":"マウス","name":"机のマウス","client_id":1}
```

GET /api/device は本人の機器を同じ形式の配列で返します。電池未設定の機器も含みます。

## 初回装着

1. 登録済みBATTERYのidを保持する。
2. POST /api/device で機器を登録し、返されたidをdevice_idとして保持する。
3. POST /api/device-battery を呼ぶ。

```json
{"device_id":10,"battery_id":20,"battery_quantity":1}
```

- device_idとbattery_idは両方とも本人所有である必要があります。
- battery_quantityは機器に入れる本数です。在庫全体のquantityとは別です。
- started_atはGoが装着時刻を設定します。入力JSONには含めません。
- Pythonへ予測を依頼し、結果をprediction_atに保存します。
- 選んだ在庫から使用本数を減らします。負数への更新はしません。
- 1機器につき使用中情報は1件です。二重装着は409になります。
- 在庫減算と使用中情報の作成はトランザクションで確定します。
- 予測失敗・在庫不足なら、その装着によるDB変更はありません。

機器登録後に装着が失敗した場合、機器は残します。Flutterは保持したdevice_idで装着を再試行します。再度POST /api/deviceする必要はありません。

## 使用中一覧とIDの取得

GET /api/device-battery の応答例:

```json
[{"id":30,"device_id":10,"device_type":"マウス","device_name":"机のマウス","battery_id":20,"battery_type":"単3形","chemical":"アルカリ","manufacturer":"テスト","battery_quantity":1,"started_at":"2026-11-19T01:00:00Z","prediction_at":"2028-07-22T15:00:00Z","recommended_replacement_date":"2028-07-23"}]
```

- idはDEVICE_BATTERYのPKです。交換・予測取得に使います。
- POSTの本文が空なので、装着後は一覧を取得し、同じdevice_idのレコードからidを取得します。
- prediction_atはTIMESTAMPTZです。日本時間の日付を表示するときは recommended_replacement_date を使えます。
- battery_typeは電池の種類、device_typeは機器の種類です。

## 電池交換

PATCH /api/device-battery:

```json
{"id":30,"battery_id":21}
```

交換対象のDEVICE_BATTERY.idと、交換用として選んだ登録済みBATTERY.idを指定します。

- 既存のbattery_quantityだけ、新しく選んだ在庫を減らします。
- 古い電池の在庫は再度減らしません。古い電池を未使用在庫へ戻す処理もありません。
- 同じ使用中レコードのbattery_id・started_at・prediction_atを更新します。
- 本数の変更・交換履歴の蓄積・使用終了は、このAPIの対象外です。
- 同時に交換が進み、推論中に対象情報が変更された場合は409を返します。
- 通信タイムアウト時にPATCHを自動再送しないでください。まず一覧を再取得して結果を確認します。リクエスト単位の永続的な重複排除キーは未実装です。

## 交換推奨日

GET /api/prediction?device_battery_id=30:

```json
{"device_battery_id":30,"recommended_replacement_date":"2028-07-23"}
```

保存済みの日付を返します。GETで再推論やDB更新はしません。初回装着・交換時にGoがPythonを呼びます。Goが自分のGET APIをHTTPで呼ぶ構成ではありません。

Pythonへ送る5項目:

| JSON | 取得元 |
| --- | --- |
| started_at | Goが設定する今回の装着時刻 |
| type | 選択したBATTERY.type |
| chemical | 選択したBATTERY.chemical |
| battery_quantity | 使用する本数 |
| manufacturer | 選択したBATTERY.manufacturer |

現在のモデルはマウス、アルカリ単3×1・単4×1・単4×2に対応します。マウス以外や未対応構成での予測付き装着は422です。日付は公開仕様を学習した参考値で、残量の実測値や寿命の保証ではありません。

## エラー

```json
{"error":{"code":"insufficient_stock","message":"not enough unused batteries"}}
```

| HTTP | 意味 |
| --- | --- |
| 400 | JSON、必須項目、数値の形式などが不正 |
| 401 | Bearerトークンなし、または無効 |
| 404 | 対象なし、または他人のデータ |
| 409 | 在庫不足、二重装着、同時更新の競合 |
| 422 | 機器・電池構成・chemicalが推論に対応しない |
| 502 | Pythonとの通信・応答に問題があり予測できない |
| 503 | DBまたはPython接続先が未設定 |
| 500 | その他の保存処理の失敗 |

/healthz・/readyzは従来どおりです。CreateClientやhealthの一部エラーは従来のテキスト本文です。エラー本文が必ずJSONであるとは決めつけないでください。
