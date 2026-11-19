# WatchDenchi・安定公開版（那覇市牧志1丁目）

- 発表時の操作はブラウザ内の保存領域（SharedPreferences）に保存され、Go APIへは依存しません。
- 在庫登録・保管場所変更・機器への割り当て・交換がローカル動作します。
- 機器をタップして「電池の状態を設定する」→「安心 / 準備 / 交換 / 未設定」を選ぶと端末に保存します。状態は手入力です（AI予測値や実測残量ではありません）。
- 那覇市牧志1丁目のみ対象。毎月第2・第4月曜日の収集日を現在の日付から自動計算します。端末の日付設定が正しい前提です。
- 乾電池・コイン型電池・充電式電池で分別案内を切り替えます。ボタン電池（LR/SR/PR）は通常収集ではなく協力店へ持ち込みます。地区の選択画面は公開版では表示しません。
- 地域別日程: https://www.city.naha.okinawa.jp/kurasitetuduki/gomi-recycling/1001934/1008614.html
- 公式の分別方法: https://www.city.naha.okinawa.jp/kurasitetuduki/gomi-recycling/1001934/1007525/1001939.html
- 充電式電池の新収集: https://www.city.naha.okinawa.jp/kurasitetuduki/gomi-recycling/1001934/1010979.html

## 公開手順とページ

PRをmainにマージするとGitHub Actionsが公開します。
- アプリ: https://track-record-shiplabhackathon.github.io/WatchDenchi_app/
- iPhone枠のページ: https://track-record-shiplabhackathon.github.io/WatchDenchi_app/presentation.html
- 以前のAPI接続試験版: /WatchDenchi_app/api-preview/（このブランチでは新規の実DB書き込みを避けるため匿名認証OFFになっています。発表では使用しません）

## 動作確認

```sh
cd FRONT
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build web --base-href /
python3 -m http.server 8080 --directory build/web
```

http://localhost:8080/presentation.html で発表用画面を表示。

### 検証すべき操作
1. 電池を在庫棚に登録→画面再読み込み後も保持。
2. 電池を機器に割り当て→在庫本数が減少。
3. 機器の状態「交換」を入力→再読み込み後も保持。
4. 在庫から機器の電池を交換→在庫が減り、機器が残る。
5. 回収日の画面で那覇市牧志1丁目と第2・第4月曜を確認。
6. 地域の公式サイトを開けることを確認。

この構成はサーバー連携の完成ではありません。発表では「現時点では端末内に保存、API連携は開発中」と説明してください。
