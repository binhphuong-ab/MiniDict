import Foundation

/// Thin client for the endpoints the oxfordlearnersdictionaries.com website itself uses.
/// There is no public JSON API for entries; we fetch the HTML page and let the
/// web view extract `#entryContent`.
enum Oxford {
    static let host = "www.oxfordlearnersdictionaries.com"
    static let base = URL(string: "https://\(host)/")!

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36",
            "Accept-Language": "en-GB,en;q=0.9",
        ]
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniDict/http", isDirectory: true)
        c.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20, directory: dir)
        c.requestCachePolicy = .returnCacheDataElseLoad   // dictionary entries rarely change
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    enum Failure: LocalizedError {
        case badURL, http(Int)
        var errorDescription: String? {
            switch self {
            case .badURL: return "URL không hợp lệ"
            case .http(let code): return "Oxford trả về lỗi HTTP \(code)"
            }
        }
    }

    static func isOxford(_ url: URL) -> Bool {
        url.scheme == "https" && (url.host == host || url.host == "oxfordlearnersdictionaries.com")
    }

    static func suggest(_ q: String) async throws -> [String] {
        var c = URLComponents(string: "https://\(host)/autocomplete/english/")!
        c.queryItems = [URLQueryItem(name: "q", value: q),
                        URLQueryItem(name: "contentType", value: "application/json; charset=utf-8")]
        var req = URLRequest(url: c.url!)
        req.cachePolicy = .useProtocolCachePolicy
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw Failure.http(h.statusCode) }
        struct R: Decodable { struct I: Decodable { let searchtext: String }; let results: [I] }
        return try JSONDecoder().decode(R.self, from: data).results.map(\.searchtext)
    }

    /// Fetches a dictionary page, following redirects (search/direct → definition or spellcheck).
    static func page(_ url: URL) async throws -> (url: URL, html: String) {
        guard isOxford(url) else { throw Failure.badURL }
        // Search redirects depend on the query, not on cacheable content.
        var req = URLRequest(url: url)
        if url.path.contains("/search/") { req.cachePolicy = .reloadIgnoringLocalCacheData }
        let (data, resp) = try await session.data(for: req)
        guard let h = resp as? HTTPURLResponse else { throw Failure.http(0) }
        guard h.statusCode == 200 || h.statusCode == 404 else { throw Failure.http(h.statusCode) }
        let html = String(decoding: data, as: UTF8.self)
        NSLog("MiniDict: \(h.statusCode) \(url.path) -> \(h.url?.path ?? "-") (\(data.count) bytes)")
        return (h.url ?? url, html)
    }
}
