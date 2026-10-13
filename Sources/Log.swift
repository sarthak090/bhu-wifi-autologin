import Foundation

let logFormatter = ISO8601DateFormatter()
let logLock = NSLock()  // log() is called from several threads

/// Appends a timestamped line to ~/Library/Logs/bhu-wifi-login.log (and stderr).
/// Never pass a password to this function.
func log(_ message: String) {
    logLock.lock(); defer { logLock.unlock() }
    let line = "[\(logFormatter.string(from: Date()))] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
    let url = CONFIG.logURL
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

let sleep = { (seconds: TimeInterval) in try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
