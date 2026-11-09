import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/** A problem in the app's own plain words: [words] are said as they are; [detail] (an HTTP code) only goes to the log. */
public struct Plain: Error, CustomStringConvertible {
    public let words: String
    public let detail: String?
    public init(_ words: String, _ detail: String? = nil) { self.words = words; self.detail = detail }
    public var description: String { detail.map { "\(words) (\($0))" } ?? words }
}

/** An answer that wasn't 2xx. */
public struct HTTPStatus: Error, CustomStringConvertible {
    public let code: Int
    public let url: String
    public var description: String { "HTTP \(code) from \(url)" }
}

/** One way onto the network for everything: lookups, YouTube Music, covers, saving (Android's net/Http.kt). */
public enum Http {
    public static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"

    public static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 600
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: c)
    }()

    public static func url(_ base: String, _ query: [String: String] = [:]) -> URL? {
        guard var c = URLComponents(string: base) else { return nil }
        if !query.isEmpty {
            // in a steady order, and with "+" escaped too (URLComponents leaves it, servers read it as a space)
            c.percentEncodedQueryItems = (c.percentEncodedQueryItems ?? []) + query.keys.sorted().map {
                URLQueryItem(name: escape($0), value: escape(query[$0]!))
            }
        }
        return c.url
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    /** The answer's body and status (any status: the caller decides). */
    public static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = session.dataTask(with: request) { data, response, error in
                if let error { return cont.resume(throwing: error) }
                guard let http = response as? HTTPURLResponse else { return cont.resume(throwing: Plain("Something went wrong. Try again.", "no HTTP answer")) }
                cont.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }

    /** The body of a 2xx answer, else an error. */
    public static func get(_ base: String, _ query: [String: String] = [:], headers: [String: String] = [:]) async throws -> Data {
        guard let u = url(base, query) else { throw Plain("Something went wrong. Try again.", "bad address \(base)") }
        var req = URLRequest(url: u)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, r) = try await send(req)
        guard (200..<300).contains(r.statusCode) else { throw HTTPStatus(code: r.statusCode, url: base) }
        return data
    }

    public static func text(_ base: String, _ query: [String: String] = [:]) async -> String? {
        guard let d = try? await get(base, query) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    /** JSON from [base], or nil (offline, not found, not JSON). */
    public static func json(_ base: String, _ query: [String: String] = [:]) async -> JSON? {
        guard let d = try? await get(base, query) else { return nil }
        return JSON.parse(d)
    }

    /** JSON from [base]; the network's own error when it can't be asked (so it can be said in plain words). */
    public static func jsonOrThrow(_ base: String, _ query: [String: String] = [:], headers: [String: String] = [:]) async throws -> JSON {
        let d = try await get(base, query, headers: headers)
        guard let j = JSON.parse(d) else { throw Plain("The answer didn't make sense. Try again later.", "not JSON from \(base)") }
        return j
    }

    public static func postJson(_ base: String, _ body: JSON, headers: [String: String] = [:]) async throws -> JSON {
        guard let u = URL(string: base) else { throw Plain("Something went wrong. Try again.", "bad address \(base)") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.httpBody = body.data()
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, r) = try await send(req)
        guard (200..<300).contains(r.statusCode) else { throw HTTPStatus(code: r.statusCode, url: base) }
        guard let j = JSON.parse(data) else { throw Plain("The answer didn't make sense. Try again later.", "not JSON from \(base)") }
        return j
    }

    /**
     * Downloads [url] into the file [to] in pieces (YouTube slows down whole-file downloads, never ranged ones).
     * [progress] gets the part done, 0-1. A half-written file isn't left behind.
     */
    public static func download(_ url: String, to dest: URL, size: Int64? = nil, headers: [String: String] = [:],
                                progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard let u = URL(string: url) else { throw Plain("The download stopped. Try again.", "bad address") }
        let part = dest.appendingPathExtension("part")
        let fm = FileManager.default
        try? fm.removeItem(at: part)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.createFile(atPath: part.path, contents: nil) else { throw Plain("Couldn't make the file.", part.path) }
        do {
            let out = try FileHandle(forWritingTo: part)
            defer { try? out.close() }
            let piece: Int64 = 4 * 1024 * 1024
            var at: Int64 = 0
            while true {
                try Task.checkCancellation()
                var req = URLRequest(url: u)
                headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
                req.setValue("bytes=\(at)-\(at + piece - 1)", forHTTPHeaderField: "Range")
                let (data, r) = try await send(req)
                if r.statusCode == 416 && at > 0 { break } // past the end: it's all here
                guard r.statusCode == 206 || r.statusCode == 200 else { throw Plain("The download stopped. Try again.", "HTTP \(r.statusCode)") }
                try out.write(contentsOf: data)
                at += Int64(data.count)
                if r.statusCode == 200 { break } // the server sent it all at once
                if let size, size > 0 { progress(min(max(Double(at) / Double(size), 0), 1)) }
                if Int64(data.count) < piece { break }
                if let size, size > 0, at >= size { break }
            }
            try out.synchronize()
        } catch {
            try? fm.removeItem(at: part)
            throw error
        }
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: part, to: dest)
        progress(1)
    }
}
