# Flutter担当者向け：主要APIの接続指示

APIの確定仕様は [api.md](api.md) にまとめています。Goの公開・DB反映を確認してから接続確認します。

## 現在のFlutterで把握したこと

2026-11-19のmainを確認しました。

- lib/main.dartでは enableServerInventory = false に固定され、通常の発表版は端末内保存です。APIを公開するだけでは画面がサーバー保存に切り替わりません。
- BatteryEntryには任意のidがあり、サーバー在庫の取得時にはBATTERY.idを保持する準備があります。
- DeviceUsageにはDEVICE.id・DEVICE_BATTERY.id・BATTERY.id・予測日を保持する項目がありません。追加が必要です。
- LocalBatteryStore.readInventory()にはサーバー取得の分岐がありますが、使用開始・交換はサーバーモードだと停止する分岐があります。新APIの呼び出しへ置き換えます。
- services/watchdenchi_api.dartにはGET/POSTだけがあり、既定のタイムアウトは8秒です。
- chemicalの送受信と既存トークンの再利用処理はあります。
- 「Goにはchemicalが保存できない」という旧警告と保管場所必須のチェックが残っています。新Goではchemicalを保存し、保管場所の空文字を許可します。

## 実装すること

1. 安定した発表用ローカル版を維持しながら、API接続を試すモードを用意する。単にビルド引数を追加しても、現在のfalse固定では切り替わらない点に注意する。
2. 既存のanonymous_session.dartを使い、保存済みトークンを再利用する。各APIにBearerを付ける。client_idは送らない。
3. watchdenchi_api.dartにPATCHを追加する。201/204の空本文を正常終了として扱う。
4. Pythonの起動待ちを考慮し、装着・交換の通信タイムアウトを90秒程度にする。操作中は送信ボタンを無効にする。
5. BatteryEntry.idを保持する。画面のchemistryをAPIのchemical、locationをstorage_locationへ対応させる。登録日時はregistered_atで受け取る。
6. DeviceUsageにid（使用中情報ID）・deviceId・batteryId・predictionAt・recommendedReplacementDateを保持する。画面側のリスト番号をDBのIDとして送らない。
7. 使用開始はPOST /api/device → POST /api/device-batteryの順。装着失敗時は機器登録を繰り返さず、保持したdevice_idで再試行する。
8. 装着後はGET /api/device-batteryで使用中情報IDを取得する。
9. 交換ではPATCH /api/device-batteryへidと交換用battery_idだけを送る。
10. 装着・交換・在庫数更新の成功後は、GET /api/batteryとGET /api/device-batteryで画面を更新する。サーバーモードではFlutterが別途ローカル在庫を減算しない。
11. 機器画面の表示はGET /api/device-batteryを基準にする。電池未設定の機器も出す場合はGET /api/deviceを組み合わせる。
12. 交換推奨日は一覧のrecommended_replacement_date、またはGET /api/prediction?device_battery_id=...から表示する。「ホーム」の表示名称は「機器画面」に統一する。内部クラス名HomePageの変更は必須ではない。
13. 予測日は「参考の交換推奨日」として表示する。既存の手入力batteryStatusやmanualReplacementAtをPythonの予測値として扱わない。
14. 401以外の通信失敗で匿名トークンを消さない。502/503時は入力を保持して再試行できるようにする。
15. タイムアウトした書き込みは自動再送しない。GET一覧で登録済みか確認する。特に交換PATCHは同じ要求の再送で再度在庫を消費し得る。

## 初回装着の入力例

POST /api/device:

```json
{"type":"マウス","name":"机のマウス"}
```

応答idをdevice_idとして、POST /api/device-battery:

```json
{"device_id":10,"battery_id":20,"battery_quantity":1}
```

成功後、GET /api/device-batteryの同じdevice_idのレコードからidを保持します。

## 交換の入力例

PATCH /api/device-battery:

```json
{"id":30,"battery_id":21}
```

API名やJSONキーは [api.md](api.md) に合わせてください。draft_idは使用しません。

## 接続確認の完了条件

- 新規電池のchemicalが登録され、一覧から同じ値を取得できる。
- マウスに単3アルカリ1本を装着すると在庫が1本減り、使用中情報と推奨日が表示される。
- 交換用の在庫が減り、古い在庫は再度減らない。
- 再読み込み後も同じ匿名トークンでサーバー上の情報を取得できる。
- 予測非対応・在庫不足では、成功したような表示やローカル在庫の減算をしない。
- 相手の機器・電池のIDを指定しても取得・変更できない。

## 今回の主要APIに含まれない機能

保管場所の移動・在庫の分割、使用終了、交換履歴の蓄積、手入力状態や回収日のサーバー保存は未実装です。それらのローカル表示を、サーバー同期済みとして扱わないでください。
