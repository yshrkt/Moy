# LaunchDaemonの利用

Moyに登録したサービスをroot権限のLaunchDaemonとして管理できる。Agentと同じ保存・有効化・無効化・再実行・削除の操作を使う。

## 新規作成と編集

GUIの新規作成でサービス種別を「LaunchDaemon」にする。既存サービスの編集とJSONインポートではkindを変更できない。インポートではファイルに指定されたkindを維持する。

CLIの新規作成では`--kind launchDaemon`を指定する。省略時はLaunchAgentとなる。

```sh
moy add --identifier boot-command --kind launchDaemon \
  --program /usr/bin/true --run-at-load
sudo moy enable boot-command
moy status boot-command
sudo moy restart boot-command
sudo moy disable boot-command
moy remove boot-command
```

定義の保存だけでは実行しない。Daemonの有効化・無効化・再実行には管理者権限が必要。有効なDaemonの実行設定の編集と削除にも権限が必要だが、表示名・説明だけの変更と、無効なDaemonの定義編集には不要。

GUIは保存前に認証する。認証をキャンセルした場合は保存せず、編集内容を維持する。CLIは必要な操作に`sudo`を付け、権限不足なら保存前に終了する。sudo実行時も元ユーザーの定義を使い、JSONやロックファイルの所有者をrootへ変更しない。

認証成功後に設定保存は成功したが反映に失敗した場合は、Agentと同じく保存成功・反映失敗を表示する。実際の状態を確認して再操作する。

## 起動時に一度実行するコマンド

RunAtLoadをON、KeepAliveをOFFにする。コマンドはrootとして実行されるため、ProgramArgumentsに`sudo`は含めない。たとえばsysctlのサービスでは、実行ファイルを`/usr/sbin/sysctl`、引数を`iogpu.wired_limit_mb=<設定値>`とする。

RunAtLoadはシステム起動時に加え、初回有効化や設定反映による再読み込み時にも実行する。終了後の「待機中」は正常で、前回の終了コードとログで結果を確認する。Moyはコマンドの効果を追跡せず、無効化・削除によって実行済みの変更を取り消さない。

plistは`/Library/LaunchDaemons/<Label>.plist`、既定ログは`/Library/Logs/Moy/<Label>.stdout.log`／`stderr.log`に配置する。定義のJSONはAgentと共通のユーザー設定ディレクトリに保存する。

## 専用ジョブによる実機確認

既存サービスやsysctlの設定値を変更せず、以下の専用ジョブで確認する。Identifierが重複していないことを確認し、別のテストと同時に実行しない。

```sh
moy add --identifier daemon-smoke-test --kind launchDaemon \
  --program /usr/bin/id --arg -u --run-at-load
sudo moy enable daemon-smoke-test
moy status daemon-smoke-test
cat /Library/Logs/Moy/com.sputnik-apps.moy.daemon-smoke-test.stdout.log
```

ログの`0`でroot実行を、前回の終了コード`0`で正常終了を確認する。plistの所有者がroot、権限が644であること、ユーザー設定ディレクトリ・JSON・ロックファイルの所有者が元ユーザーのままであることを確認する。

GUIで同じサービスを開き、実行設定の変更を保存して認証をキャンセルする。JSONとplistが変更されず、入力が残り、エラーが表示されないことを確認する。次に認証して保存し、再実行と状態表示、認証終了後のウィンドウ復帰を確認する。

確認後は必ず登録を撤去する。

```sh
sudo moy disable daemon-smoke-test
moy remove daemon-smoke-test
```

`launchctl print system/com.sputnik-apps.moy.daemon-smoke-test`で未登録、plistの不存在を確認する。ログは仕様どおり残るため、必要ならテスト用の2ファイルだけを管理者権限で削除する。

## 今回の確認状況

- 自動テスト：Daemonの保存・入出力、kindの変更制限、systemドメインの状態取得、権限不足時の保存防止、GUIの認証キャンセル・メタデータ編集、元ユーザーへの子プロセス委譲、定義変更の検出を確認済み。
- Debug／Releaseビルド、format、lintを確認済み。
- 管理者認証を伴う実機の登録・再実行・解除、ファイル所有権・ログ出力、再起動後の実行は未確認。非対話のsudoがパスワードを要求するため、この実行環境では検証できなかった。上記の専用ジョブで確認する。
