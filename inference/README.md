# マウスの電池交換日を返すPython API

`Go → HTTP/JSON → Python/FastAPI → 学習済み回帰木 → 交換推奨日`の順で処理します。
機器はマウスに固定し、型番・消費電力・電流・使用時間の入力は追加しません。

## モデルが学習したこと

メーカー公表の寿命15件から、`type`と`battery_quantity`を使って参考寿命の日数を推定する回帰木を学習しました。
手で寿命を設定したルール表ではありません。学習した分岐・葉の値をJSONへ書き出し、実行時はその木をたどります。
アルゴリズムは[scikit-learn DecisionTreeRegressor](https://scikit-learn.org/stable/modules/generated/sklearn.tree.DecisionTreeRegressor.html)、`criterion=absolute_error`、`max_depth=2`、`random_state=42`です。
入力条件が3種類しかないため、学習後の値は実質的に電池構成別の中央値です。複雑なモデルによる精度向上を主張するものではありません。

| 指定された入力 | 取得元 | 今回の役割 |
| --- | --- | --- |
| `started_at` | DEVICE_BATTERY.started_at | 推論日数を足す起点。学習の特徴量にはしない |
| `type` | battery_idで取得したBATTERY.type | 単3/単4に正規化して推論に使用 |
| `chemical` | battery_idで取得したBATTERY.chemical | アルカリかを確認。別の化学系へ外挿しない |
| `battery_quantity` | DEVICE_BATTERY.battery_quantity | 機器に入れた本数を推論に使用。在庫数量とは別 |
| `manufacturer` | battery_idで取得したBATTERY.manufacturer | 受け取り・確認・応答に保持。メーカー別の補正はしない |

電池メーカーの違いを学習できる資料は今回ありません。マウスメーカーを電池メーカーと取り違えて学習しない設計です。
新品の同種類・同状態の電池を同時に入れた前提です。使用済み電池の再利用には予測を適用できません。

## 検証結果と対応範囲

製品系列単位で学習から除外した評価：モデルの平均絶対誤差は約238.7日、全製品の中央値を返す基準は約256.7日です。
平均絶対誤差は、公表寿命から予測が平均で何日ずれたかを示します。239日の保証幅や信頼区間という意味ではありません。
実際の電池交換日との誤差は未評価であり、今回の精度はデモ用途です。

| 構成 | 資料件数 | 学習済みモデルから返る参考日数 |
| --- | --- | --- |
| 単3アルカリ × 1 | 11 | 612日 |
| 単4アルカリ × 1 | 2 | 223日（222.5日の四捨五入） |
| 単4アルカリ × 2 | 2 | 471日 |

マンガン・ニッケル水素・単3×2本など、今回資料がない構成はHTTP 422で理由を返します。
本数をそのまま寿命に掛ける処理はありません。資料にある電池パック全体の寿命から学習しています。

## 起動する

Python 3.12を使用します。検証に使ったPythonは3.12.6です。
以下は、`inference/`を作業ディレクトリとするコマンドです。チームのUbuntu環境では次のとおりです。

```bash
cd ~/WatchDenchi_app/inference
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.lock.txt
python -m unittest discover -s tests -v
python -m uvicorn app:app --host 127.0.0.1 --port 8001
```

別作業フォルダのWindows環境では、親フォルダに検証済み`.venv`があります。

```powershell
# 作業ディレクトリ：このREADMEがあるinferenceフォルダ
..\.venv\Scripts\python.exe -m uvicorn app:app --host 127.0.0.1 --port 8001
```

ブラウザで`http://127.0.0.1:8001/docs`を開くと、入力・実行を試せます。
推論時のWeb検索、外部AIのAPIキー、DBへの直接接続は不要です。

## リクエストと応答

`POST /predict`に以下のJSONを送ります。

```json
{
  "started_at": "2026-11-19",
  "type": "単3",
  "chemical": "アルカリ",
  "battery_quantity": 1,
  "manufacturer": "Panasonic"
}
```

Ubuntuでは、別ターミナルから次を実行します。

```bash
cd ~/WatchDenchi_app/inference
curl -i http://127.0.0.1:8001/predict \
  -H 'Content-Type: application/json' \
  --data-binary @demo_request.json
```

PowerShellでは次を実行します。

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8001/predict -ContentType 'application/json; charset=utf-8' -Body (Get-Content -Raw -Encoding UTF8 demo_request.json)
```

`recommended_replacement_date`に装着日＋推論日数を返します。
APIは追加の早期交換係数を設けず、その参考日をアプリ上の交換推奨日とする方針です。実際にその日までもつという保証はありません。

| 応答項目 | 意味 |
| --- | --- |
| `recommended_replacement_date` | YYYY-MM-DD形式の交換推奨日（参考） |
| `estimated_service_days` | 装着時点からの参考寿命。現在からの残り日数ではない |
| `days_until_replacement` | 今日から推奨日までの日数。過ぎていれば0 |
| `status` | estimated / due_today / overdue |
| `as_of` | 計算に使用した日本時間の現在日付 |
| `normalized_input` | サイズ・化学系・装着日を正規化した入力 |
| `method`, `model_version` | 推論方式とモデルの識別情報 |
| `learned_fields` | 今回データから学習できた項目 |
| `reference_data` | 対応する資料の件数・最小最大日数・出典URL。範囲は予測区間ではない |
| `assumptions`, `warnings`, `quality` | 使用条件と限界。画面にも交換日が参考値であることを表示する |

装着日はYYYY-MM-DDか、時差付きの日時（例：`2026-11-19T10:00:00+09:00`）を受け取ります。日時は日本時間の日付へ変換します。
未来の日付、0本、小数の本数、未知の化学系、追加の型番フィールドなどは422です。
過去の推奨日を現在日付に書き換えません。期限超過の場合は元の推奨日と`overdue`を返します。

`GET /healthz`で起動とモデル読み込みを確認し、`GET /model`で学習件数・対応条件・評価を確認できます。

## 自分で学習し直す

```bash
# 作業ディレクトリ：inference/
python train.py
python -m unittest discover -s tests -v
```

`data/mouse_specs.csv`を読み、製品系列を外して評価した後、全15件で最終モデルを学習します。
結果は`model/mouse_tree.json`と`model/evaluation.json`です。JSONの推論が学習ライブラリの推論と一致することも学習時に確認します。
APIは起動時にモデルを読むので、再学習後はAPIを再起動します。

`requirements.lock.txt`は検証に使った依存関係を固定しています。実行時にscikit-learnは不要ですが、学習とテストを再現しやすいよう一式を記録しました。
APIだけ起動したい場合は`requirements.txt`、学習・テストの直接依存だけを指定したい場合は`requirements-train.txt`を使えます。

## Goとの接続

Goでログイン利用者の権限を確認し、対象のDEVICE_BATTERYと、そのbattery_idに対応するBATTERYを取得します。
上の表の5項目だけをJSONにまとめ、Pythonの`POST /predict`へ送ります。DB接続・ユーザー認証・予測結果の保存はGo側で扱います。
Pythonにclient_id、認証トークン、DBの接続URLを送る必要はありません。

ローカルではPythonを8001番、既存のGoを8080番で別々に起動できます。
GoからのHTTP呼び出しには、例えば10秒のタイムアウトを設定し、Pythonからの非200応答を成功として扱わないようにします。
Pythonへの接続が失敗した場合に架空の交換日を返す実装は避け、予測が利用できない状態をFlutterへ返します。

確認したGitHub mainのBATTERYテーブルには、まだ`chemical`がありませんでした。またDEVICE_BATTERYもmainでは確認できませんでした。
現在の作業ブランチを確認し、Go側の連携時に該当項目を準備する必要があります。`chemical`を製造元やサイズから決めつけて埋めないでください。

## Renderへ公開する場合

この手順は[Render公式のFastAPI公開手順](https://render.com/docs/deploy-fastapi)に合わせた案です。Pythonサービス用のWeb Serviceを別に用意します。

| 設定 | 値 |
| --- | --- |
| Language | Python 3 |
| Root Directory | inference |
| Build Command | python -m pip install -r requirements.txt |
| Start Command | python -m uvicorn app:app --host 0.0.0.0 --port $PORT |
| Health Check Path | /healthz |

Render上のGoから、ローカルPCの`127.0.0.1:8001`へは接続できません。Go側の接続先を、デプロイしたPythonサービスのURLに設定します。
このAPIは入力された5項目だけを計算し、DBや秘密情報は保持しません。公開URLで運用するときは、そのURLへ外部からも呼び出せる構成であることをチームで把握してください。

`.github/workflows/inference.yml`はGo・Flutterと独立したPython用CI案です。PRとmainへのpush時に、固定した依存関係で再学習の再現性とAPIを確認します。
現在の作業ではGitHub Actions上の実行・Renderへのデプロイはまだ行っていません。

## 発表での説明例

「マウスを対象に、メーカー公開仕様15件から交換日の目安を返す回帰モデルを学習し、Goから呼べる独立したPython APIにしました。
型番を入力せず、電池サイズと本数から参考日数を推定して、電池を入れた日へ加えます。
公表仕様を外して評価した平均誤差は約239日と大きく、実際の交換履歴による精度検証は今後の課題です。
電池メーカー別のデータがないことも確認し、根拠のないメーカー補正は加えていません。」
