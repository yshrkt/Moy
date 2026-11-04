# MoyMetrics

macOS 26以降のプロセスをPIDで指定し、CPU使用率とメモリ使用量を計測する独立モジュール。Tuistの静的フレームワークとして管理し、FoundationとDarwin以外のモジュールには依存しない。

## 利用例

```swift
import MoyMetrics

let monitor = try ProcessMonitor(
    pids: [1234, 5678],
    metrics: [.cpu, .memory],
    interval: .seconds(2)
)

let events = try await monitor.events()
let consumer = Task {
    for await event in events {
        switch event {
        case let .samples(batch):
            for sample in batch.samples {
                // sample.pid、identity、timestampと各計測値を利用する。
                print(sample.pid, sample.cpuPercent, sample.memoryBytes)
            }
        case let .processEnded(pid, _, reason):
            print(pid, reason)
        case .finished:
            break
        }
    }
}

try await monitor.add([9012])
await monitor.remove([1234])
try await monitor.setPIDs([5678, 9012])

// 明示的な終了。finishedイベントの後にStreamが閉じる。
await monitor.finish()
await consumer.value
```

`events()`は1セッションにつき1回だけ呼び出せる。初回呼び出し時に即時計測し、その後は指定間隔の待機と計測を繰り返す。取得処理は直列で、実際の周期には取得に要する時間も含む。生成しただけでは周期的な計測は開始しない。正のPID、正の更新間隔、有効なOptionSetのビットだけを受け付ける。

計測項目はセッション作成時に固定する。`ProcessMetrics`の`.cpu`・`.memory`・`.gpu`を組み合わせ、`.all`で全項目を要求できる。空集合はプロセスの生存確認だけを行う。未選択の項目は計算せず、CPUとメモリの両方が未選択ならリソース情報の取得APIも呼び出さない。CPU・メモリは同じOS APIから取得する。

## 計測値

- CPUはuser時間とsystem時間の合計の差分を、実際の取得間隔で割った値。1コアを使い切ると100%となり、複数コアでは100%を超える。CPUカウンターと経過時間はともにMach absolute timeを使用する。初回、取得失敗後、カウンターが巻き戻った後は基準値を取り直し、`waiting`を返す。
- メモリは`proc_pid_rusage`の`ri_phys_footprint`をバイト単位で返す。topのMEM列、アクティビティモニタの「メモリ」列と同じphysical footprintを扱う。RSSには切り替えない。取得時刻・丸め・対象の集約方法による表示差はあり得る。
- GPUは初回実装の対象外。選択されている場合は`unsupported`、未選択なら`notRequested`を返す。

各指標は`MetricValue`で、`value`・`waiting`・`unsupported`・`failed`・`notRequested`を区別する。`failed`はOS API名とerrnoなどの型付き情報を保持し、ローカライズされた文言は持たない。ある指標の取得失敗で他の指標の取得を中止しない。サンプルには取得時刻とPID・プロセス開始時刻を含む。識別情報が一度も取得できていない場合、`identity`はnilとなる。

## 対象の変更と終了

`add`は未登録のPIDを追加し、既存PIDには何もしない。`remove`は対象から外して`processEnded(..., reason: .removed)`を送る。`setPIDs`は監視対象全体を置き換える。追加・置き換えの引数は変更前に検証し、不正なPIDが混ざっていても部分的に変更しない。継続するプロセスの識別情報とCPU基準値は維持する。

対象のプロセスは追加時に識別情報を取得して固定する。識別情報を取得できない場合は失敗を通知し、後の周期で再試行する。対象が既に終了していた場合は追跡を開始しない。計測の前後にも開始時刻を確認し、別プロセスへのPID再利用を検知すると`pidReused`、プロセスの終了を検知すると`exited`を通知してその対象を外す。識別情報自体の取得に失敗した場合は、終了と決めつけず、基準値をクリアして再試行する。

計測結果は1周期分をまとめ、PID昇順で返す。各PIDの値は合算しない。ある対象の終了後も他の監視は継続する。対象が0件でもStreamを維持し、後から追加できる。この間は空のサンプルやプロセス情報の取得は発生しない。明示的に同じPIDを追加し直した場合は新しい監視対象となる。子プロセスの探索・合算は行わない。

`finish()`は何度呼んでもよく、以降の追加・置き換え・購読開始は`ProcessMonitorError.finished`となる。終了後のセッションの再利用はできない。

## 購読とキャンセル

イベントを順番に受け取る単一購読者向けのAsyncStreamとする。終了通知が遅い購読者によって失われないよう、イベントは順序を保ってバッファリングする。呼び出し側は継続的に消費し、長時間の処理を各イベントの受信ループ内で行わない。画面間の配信・最新値の保持は利用側で管理する。

購読Taskをキャンセルすると、次のStreamの受信でキャンセルを検知し、`onTermination`から監視Taskを停止する。受信ループ内の別処理を実行している場合は、その処理もキャンセルに応答させる。キャンセル後の終了イベント受信には依存しない。単にループを`break`した場合は自動停止に依存せず、`finish()`を呼ぶ。監視インスタンスは利用中保持し、解放時には内部TaskとStreamを終了する。

## 検証

`mise run generate`でプロジェクトを生成し、`mise run test`で既存モジュールと合わせてテストする。`MoyMetrics`専用のビルド・テスト用schemeも用意する。

通常の計算・ライフサイクルテストは差し替えたReaderで、CPUの差分・100%超・失敗後の基準値・PID再利用・複数PIDの追加削除を確認する。実際のOS APIはテストプロセス自身と専用の子プロセスを対象に確認し、ユーザーのサービスやlaunchd登録は変更しない。
