# API接続版の動作確認

公開先（Go API接続版）: https://track-record-shiplabhackathon.github.io/WatchDenchi_app/
旧API接続版URL（互換）: https://track-record-shiplabhackathon.github.io/WatchDenchi_app/api-preview/
発表用ローカル保存版: https://track-record-shiplabhackathon.github.io/WatchDenchi_app/offline/
iPhone枠つき発表用: https://track-record-shiplabhackathon.github.io/WatchDenchi_app/presentation.html

通常の公開先はGo API接続版です。ローカル保存版は/offline/に独立して置いています。API接続版はビルド時の
WATCHDENCHI_ENABLE_SERVER_AUTH と WATCHDENCHI_ENABLE_SERVER_INVENTORY を true にし、
Go と PostgreSQL を使います。匿名トークンは既存の保存処理を再利用し、client_id は送りません。
ローカル在庫をサーバーへ自動移行する処理はありません。

## 確認する操作

1. 在庫棚で「単3形・アルカリ・任意のメーカー・3本」を登録する。
2. 登録した電池から使用する操作を開き、機器アイコンに「マウス」を選び、1本装着する。
3. 機器タブで名前と「交換目安（参考）」を確認する。
4. 電池を交換し、在庫がもう1本減り、装着時刻と交換目安が更新されることを確認する。
5. 再読み込みしても在庫と機器が復元されることを確認する。

API操作の成功後にGoから一覧を取得します。POST/PATCHが失敗・タイムアウトしても自動再送しません。
装着失敗時は未設定の同名マウスを再利用します。交換の二重実行を避けるため、失敗時は一覧を確認してください。

予測対象はマウス、対応するアルカリ乾電池の構成に限定されます。
交換目安は公開仕様を学習したデモ用の参考日であり、実測残量ではありません。
手入力の電池状態・保管場所移動・使用終了履歴・処分日情報のサーバー保存は今回の接続対象に含めません。
