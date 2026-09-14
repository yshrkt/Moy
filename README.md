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

現時点ではプロジェクトの土台のみです。アプリとCLIはプレースホルダーで、サービス管理機能とテストケースは今後追加します。
