# Python推論サービス（☆2）

Goから内部HTTP APIで呼び出し、物理式による推定値を補正する予定です。FlutterはGo APIを呼び出します。学習済みモデル、入力・出力、評価用データ、実行環境の決定後に実装します。

採用候補はFastAPIです。モデルの依存と動作確認できた版を合わせて固定し、推論コードとテストを追加するPRで記録します。☆1の起動、DBマイグレーション、CIにPythonサービスは不要です。 [FastAPI公式のバージョン固定ガイド](https://fastapi.tiangolo.com/deployment/versions/)
