# WatchDenchi 発表用表示

このブランチでは、main のデザインを保持しつつ、機器アイコン右上に以前の小さな電池ステータスバッジを戻しています。

- 通常の機器画面: 予測APIが未連携なので「未設定」。保存済みデータは変更しません。
- 発表用デモ: FlutterのURLに `?demoBadges=1` を付けると、機器ごとに「安心」「準備」「交換」「未設定」の見本色分けを表示します。実際の電池残量や交換予測ではありません。
- iPhone枠: `FRONT/web/presentation.html` は以前の発表用HTMLをそのまま復元したものです。

ローカルで確認:

```sh
cd FRONT
flutter pub get
flutter build web --base-href /
python3 -m http.server 8080 --directory build/web
```

- 枠つき通常版: http://localhost:8080/presentation.html
- 枠つきバッジデモ: http://localhost:8080/presentation.html?app=./%3FdemoBadges%3D1

このブランチをGitHub Pagesで公開するにはPRのマージとActions実行が必要です。ブランチを作っただけでは現在の公開URLは変わりません。
