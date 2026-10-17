# プロジェクト概要

Moyは、CLIで動くサービスをユーザー単位のLaunchAgentとして管理するmacOS用メニューバーアプリです。GUIと同梱CLIから、共通のサービス定義と操作を利用します。

## 仕様・実装方針の参照先

- 作業を始める前に、[実装プラン](docs/plan.md)を読んでください。対象OS、設定項目、Label、JSON保存、操作の意味、初期版の範囲、完成条件はこのプランを基準にしてください。
- このファイルには開発ルールを記載し、詳細な仕様は`docs/plan.md`に集約してください。
- 会話で仕様変更が決まった場合は、対象のドキュメントにも反映し、実装とプランの整合性を保ってください。
- プロジェクト構成・命名・Tuist設定はMiroCalを参考にします。Moy固有の構成と仕様は`docs/plan.md`を優先してください。

# 全体ルール

- ドキュメント類は、指定がない限り日本語で作成してください。
- 仕様相談・計画の段階では実装を開始しないでください。ユーザーから実装・修正を依頼された範囲は、その依頼を承認として進め、同じ承認を繰り返し求めないでください。
- ソースコードを追加・編集したらフォーマッターを実行し、変更に応じたビルド・テスト・lintを行ってください。
- 実行できなかった確認項目は、その理由とともに報告し、未実施の確認を成功扱いしないでください。

# コマンド実行

このプロジェクトは`mise`と`tuist`を利用します。プロジェクト内の`mise.toml`でツールとタスクを管理してください。

開発環境はXcode 27・同梱のSwift 6.4を使用します。`.swift-version`とSwift Packageのtools versionは6.4、`Project.swift`の`SWIFT_VERSION`は言語モードを表すため`6.0`としてください。

コマンドが見つからない場合は、シェル環境とプロジェクトの設定を確認してください。必要に応じて次を実行します。

```bash
source ~/.zprofile
mise install
```

## 基本コマンド

- `mise run generate`: 依存解決とXcodeワークスペースの生成。
- `mise run build`: ビルド。
- `mise run test`: テストの実行。
- `mise run format`: フォーマッターの実行。
- `mise run lint`: lintの実行。

初期構築時にこれらのタスクを用意してください。実行前に`mise.toml`の定義を確認し、生成済みのXcodeプロジェクトや文字列アクセサーを直接編集せず、Tuist定義や元のリソースを変更してください。

# モジュール構成・ファイル配置

| 配置 | 責務 |
|---|---|
| `Sources/MoyApp/Core/<機能名>` | NanoReduxのAction／State／Reducer／Dependencies |
| `Sources/MoyApp/Platform` | 認証・CLI導入などのmacOS固有実装 |
| `Sources/MoyApp/Views` | SwiftUIの画面・コンポーネント |
| `Sources/MoyApp/MoyApp.swift` | アプリのエントリーポイントと依存の組み立て |
| `Sources/MoyCLI` | CLIの引数解析・表示・エントリーポイント |
| `Sources/MoyKit/Domain/Models` | Entity／ValueObject／状態・エラーの型 |
| `Sources/MoyKit/Domain/Repositories` | Repositoryのprotocol |
| `Sources/MoyKit/Domain/UseCases` | UseCaseのprotocol |
| `Sources/MoyKit/Platform/Repositories` | JSON保存などのRepository実装 |
| `Sources/MoyKit/Platform/UseCases` | launchd操作などのUseCase実装 |
| `Resources/MoyApp` | GUI用ローカライズ、アセット、アプリ設定 |
| `Tests/MoyAppTests` | GUIの状態管理などのテスト |
| `Tests/MoyCLITests` | CLIの引数解析・出力などのテスト |
| `Tests/MoyKitTests` | 共通モデル・保存・launchd操作などのテスト |

- 依存関係は`MoyApp → MoyKit`、`MoyCLI → MoyKit`としてください。
- NanoReduxはMoyAppだけで使用し、MoyKitとMoyCLIには依存させないでください。
- DomainのprotocolとPlatformの具体実装を分離し、テストで差し替えられるようにしてください。
- JSON保存・Label生成・plist生成・launchctl操作はMoyKitに集約し、GUIとCLIで重複実装しないでください。

# 状態管理・命名ルール

## NanoRedux

機能ごとにAction／State／Reducer／Dependenciesを分割し、`Sources/MoyApp/Core`配下の同じ機能ディレクトリに配置してください。

例：

- `ServicesAction.swift`
- `ServicesState.swift`
- `ServicesReducer.swift`
- `ServicesDependencies.swift`

メニューバーと管理ウィンドウでStoreを共有し、機能ごとにscopeしてください。画面の変更はAction／Reducerを通し、保存・launchd操作・状態取得はEffectから依存注入したUseCaseを呼び出してください。

## Store Action

原則として`verbObject`形式で統一してください。

- 使用例：`appear`、`enableService`、`disableService`、`restartService`、`receiveServiceStatuses`、`openSettings`。
- 避ける例：`onAppear`、`didAppear`、`enableServiceTapped`、`didTapEnableService`。

## UseCase

- Protocol: `...UseCase`。
- 既定実装: `Default...UseCase`。

# ローカライズ・エラー表示

- GUIは日本語・英語に対応し、`Resources/MoyApp/ja.lproj`と`Resources/MoyApp/en.lproj`に文字列を配置してください。
- MiroCalと同様に`Localizable.strings`からTuistで生成した`L10n`経由で参照してください。
- `Localizable.strings`を追加・変更した場合は、`mise run generate`を実行してください。
- 日英のキーと書式引数を一致させ、メニュー・説明・確認・エラー・アクセシビリティラベルもローカライズしてください。
- CLIのヘルプとメッセージは英語のみとし、CLI用のローカライズbundleは設けないでください。
- MoyKitは型付きエラーを返し、MoyAppで日英、MoyCLIで英語のメッセージに変換してください。
- ユーザー入力の表示名・descriptionや、Label・plistキー・JSONキー・機械可読な状態値は翻訳しないでください。

# 検証

- 検証項目と完成条件は[プランの「検証と完成条件」](docs/plan.md#5-検証と完成条件)を参照してください。
- ファイル保存やlaunchctl実行の依存を差し替え、通常のユニットテストは一時ディレクトリとテスト用実装を使ってください。
- 実機でlaunchdを検証する場合は専用のテストジョブを作り、ユーザーの既存サービスを変更せず、テスト後に登録を撤去してください。
