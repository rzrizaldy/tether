import Foundation

/// A plain text log at ~/Library/Logs/Tether.log, so "it didn't connect" can be
/// answered by reading what actually happened.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Tether.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            if (try? h.seekToEnd()) ?? 0 > 2_000_000 { try? h.truncate(atOffset: 0) }
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
