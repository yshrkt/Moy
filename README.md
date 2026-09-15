# Moy

CLIサービスをlaunchdで管理するmacOS用メニューバーアプリです。

仕様と実装方針は[実装プラン](docs/plan.md)、開発ルールは[AGENTS.md](AGENTS.md)を参照してください。

## 開発環境

- macOS 26以降
- Xcode 27（Swift 6.4）
- mise

Tuist・SwiftFormat・SwiftLintのバージョンは`mise.toml`で固定しています。SwiftはXcode同梱のツールチェーンを使用し、`.swift-version`は6.4、プロジェクトの言語モードはSwift 6に設定しています。

複数のXcodeを利用している場合は、`xcodebuild -version`と`xcrun swift --version`でXcode 27／Swift 6.4が選択されていることを確認してください。

```bash
mise install
mise run generate
```

`Moy.xcworkspace`が生成されます。Xcodeで開き、`Moy`スキームを選択してください。

| コマンド | 内容 |
|---|---|
| `mise run generate` | 依存解決・Xcodeワークスペース・文字列アクセサーの生成 |
| `mise run build` | アプリと同梱CLIのビルド |
| `mise run test` | 各モジュールのテスト実行 |
| `mise run format` | SwiftソースとTuist定義の整形 |
| `mise run lint` | SwiftLintによるチェック |

ビルド先は`build/`です。ローカル開発用の署名でビルドし、CLIは`Moy.app/Contents/Helpers/moy`へ同梱します。配布用署名は未設定です。

## モジュール

- `MoyApp`: SwiftUI・NanoReduxによるGUI。日本語・英語に対応。
- `MoyCLI`: 英語のCLI。製品名は`moy`。
- `MoyKit`: GUIとCLIで共通利用するDomain・Platform層。

MoyKitとMoyCLIには、サービス定義のJSON保存、plist生成、`launchctl`による有効化・無効化・再実行、状態取得を実装しています。RepositoryとUseCaseは`async throws`で、同一プロセス内はactor、App／CLI間はファイルロックで直列化します。MoyAppの管理画面では、サービスの一覧・詳細・登録・編集・削除を提供します。

## 設定

サービス一覧の左ペイン左下の歯車、またはメニューバーの「設定…」から、共通の設定ウィンドウを開きます。「設定」タブでCLIのインストール、「情報」タブでアプリのバージョン・ビルド番号を確認できます。

「コマンドラインツール」の「インストール」を押すと、同梱CLIへのリンクを `/usr/local/bin/moy` に作成します。既存ファイルや別のリンクは上書きしません。設定画面を開いたときに実際のリンクを確認するため、アプリ再起動後もインストール状態が反映されます。

`/usr/local/bin` に書き込み権限がない場合は、macOSの管理者認証ダイアログが表示されます。認証はMoyプロセス内の `NSAppleScript` から要求します。認証はリンクのインストールだけに使用し、サービス操作は通常ユーザー権限で行います。認証をキャンセルするとインストールを中止します。旧バージョンで作成した `~/.local/bin/moy` は自動削除しません。

通常、`/usr/local/bin` はPATHに含まれています。新しいターミナルで `moy --help` を実行して確認してください。コマンドが見つからない場合は、シェルのPATHに `/usr/local/bin` が含まれているか確認してください。

## CLI

ビルド後のCLIは`build/Build/Products/Debug/moy`に生成され、`Moy.app/Contents/Helpers/moy`にも同梱されます。

```bash
# 定義を保存する（plistの作成やbootstrapはまだ行わない）
build/Build/Products/Debug/moy add \
  --identifier web-server \
  --name "Local web server" \
  --description "Serves the public directory" \
  --program /usr/bin/python3 \
  --arg -m \
  --arg http.server \
  --working-directory "$PWD/public" \
  --env PORT=8080 \
  --run-at-load

# Identifierを指定して操作する
build/Build/Products/Debug/moy enable web-server
build/Build/Products/Debug/moy status web-server
build/Build/Products/Debug/moy restart web-server
build/Build/Products/Debug/moy logs web-server
build/Build/Products/Debug/moy disable web-server
```

`add --enable`では保存と有効化を一度に行えます。`list`、`show`、`status`、`logs`は`--json`に対応しています。すべてのコマンドとオプションは`moy --help`および`moy <command> --help`で確認できます。CLIのヘルプとメッセージは英語です。

定義は`~/Library/Application Support/Moy/services.json`、有効なサービスのplistは`~/Library/LaunchAgents/<Label>.plist`、既定のログは`~/Library/Logs/Moy/`に保存されます。Identifierは1〜64文字の小文字英数字・ハイフン・アンダースコアで指定し、作成後は変更できません。Labelは`com.sputnik-apps.moy.<Identifier>`として生成されます。表示名は任意で、未設定の場合はIdentifierを表示します。

- `enable`: plistを作成してユーザーのGUIドメインへ`bootstrap`する
- `disable`: `bootout`を確認してplistを削除する。定義とログは残す
- `restart`: 読み込み済みのサービスを`kickstart -k`する
- `remove`: 必要なら無効化してから定義を削除する。ログは残す
