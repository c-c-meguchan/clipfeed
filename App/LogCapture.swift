import Foundation

/// 実行ログをメモリに蓄積し、設定画面の「ログを出力」でファイルに含めるためのキャプチャ。
/// stdout はリダイレクトせず、record() で print とバッファへの追記の両方を行う。
enum LogCapture {
    private static let lock = NSLock()
    private static var buffer: [String] = []
    private static let maxLines = 1000

    /// エクスポート時の表示用（「直近 N 行」の N）
    static var maxLinesDisplay: Int { maxLines }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// 1行を記録する。コンソールにも出力し、バッファにも追加する（スレッドセーフ・最大行数で打ち切り）。
    static func record(_ message: String) {
        print(message)
        lock.lock()
        defer { lock.unlock() }
        let timestamp = timeFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        buffer.append(line)
        if buffer.count > maxLines {
            buffer.removeFirst(buffer.count - maxLines)
        }
    }

    /// 蓄積したログを改行区切りで返す。エクスポート用。
    static func getContent() -> String {
        lock.lock()
        defer { lock.unlock() }
        return buffer.joined(separator: "\n")
    }
}
