import Foundation

/// Lookup history, saved words and stats live in one JSON file the web UI owns.
/// Swift only loads and saves it, so it outlives the web view's own storage
/// (which gets cleared with website data) and is easy to back up or inspect.
///
///   ~/Library/Application Support/MiniDict/data.json
enum Store {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniDict", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }()

    static func load() -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func save(_ json: String) {
        // Refuse anything that isn't a JSON object, so a bug can't wipe the file with garbage.
        guard let data = json.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            NSLog("MiniDict: refused to save invalid data"); return
        }
        do { try data.write(to: url, options: .atomic) }
        catch { NSLog("MiniDict: saving data failed: \(error)") }
    }
}
