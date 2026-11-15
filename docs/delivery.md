# GitHub Actionsと配布

`main` 宛てPR、`main` へのpushで3ジョブを実行します。

- **Go API** は整形・依存・vet・race付きテスト・ビルド。Linux amd64ビルドは元コミットとGoビルド情報を同梱し、コミットSHAを名前に含むActions成果物として保存。
- **PostgreSQL integration** は一時DBにマイグレーションを適用し、Goの準備状態とSQLの読み書きを検証。
- **Flutter** はSDKと依存ロックを固定し、整形・静的解析・Widgetテストを実行。

外部Actionは検証したコミットの完全SHAで固定します。Pythonのチェックはコード追加時、OpenAPIのチェックは契約をOpenAPIで管理する段階で加えます。

## mainの保護

リポジトリの Settings → Branches で、保護対象を `main` に指定します。
PRを必須にし、GitHub Actionsでジョブが表示された後に、`Go API`、`PostgreSQL integration`、`Flutter` の成功をマージ条件に選択します。
force pushと削除は許可しません。レビューは運用で行い、他の承認者が対応できると確認してから承認数を1以上にします。
担当者が決まったらCODEOWNERSの適用を検討します。
[GitHubのブランチ保護](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

## 配置の候補

| 候補 | 費用を左右する点 | 運用作業 |
| --- | --- | --- |
| ローカルPCでデモ | 手持ちPCで実行すれば追加クラウド費用なし | 実行中のPCと通信経路を維持。バックアップも自分たちで管理 |
| 管理型のコンテナとPostgreSQL | APIの利用量とDBの稼働時間・容量。DB費用も確認 | HTTPS、秘密情報、DB接続、配置用のコンテナとマイグレーションの設定 |
| VMとPostgreSQL | VMの稼働時間・ストレージ・通信量 | OS更新、HTTPS、監視、バックアップと復旧を管理 |

配置先、デモ端末・対象OSと配布方法が決まったら、テスト環境から接続します。GoのActions成果物があり、デプロイ先・Flutter署名への自動配布は未接続です。
AndroidはAPKやAABの目的と署名を、iOSはmacOSのビルド環境と署名・プロビジョニングを配布方法に合わせて決めます。
[Flutterの継続的デリバリー](https://docs.flutter.dev/deployment/cd)

必要な設定は配置先、Goの待ち受け、PostgreSQLの接続URLとTLS・認証、クライアントからのHTTPS接続先、ストア配布に必要な署名情報です。
GitHub Environmentsの利用条件とレビュー担当を確認し、配置先が対応する場合はOIDCを使います。公開されるFlutter設定に秘密情報を含めません。
[GitHub Environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) · [GitHub OIDC](https://docs.github.com/en/actions/concepts/security/openid-connect)

1. CIに合格したコミットの成果物をテスト環境に使う。本番初回は手動または承認付きで開始。
2. DBをバックアップし、前のアプリ版でも動くマイグレーションから適用。失敗したら配置を止め、DB状態を確認する。
3. APIを更新し、`/healthz`、`/readyz` と利用者の基本操作を確認。障害時は前の成果物へ戻す。
4. DB変更の復旧は、後続の修正マイグレーションまたはバックアップからの復元を別途検討する。開発用初回SQLは再実行可能。本番で変更履歴を適用・記録する方法は配置先を決定後に整備する。
