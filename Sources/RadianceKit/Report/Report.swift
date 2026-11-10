import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 * Report a Problem (Android's report/Report.kt; owner 2026-11-02, chosen in a dialog; the computer has the same): the
 * person sees exactly what will be sent, may add a note, and presses Send. Nothing leaves without that press. It goes
 * to admin.radianceph.com (POST /api/music/reports, radianceph#43; "ios" taken since radianceph#63).
 *
 * The iPhone keeps no log file of its own: the app's lines in the iPhone's log are read back (an app may read its own,
 * this run's), newest part only, with email addresses taken out.
 */
public enum Report {
    /** The admin's limits: the note in characters, the log in UTF-8 bytes (its own is 204,800), the system in characters. */
    public static let mostNote = 2000
    public static let mostLog = 200_000
    public static let mostSystem = 500
    /** Sent instead of an empty log (the admin needs one). */
    public static let noLog = "(the app's log is empty)\n"
    public static let admin = "https://admin.radianceph.com"

    /** What will be sent, shown in full before Send. */
    public struct What: Equatable, Sendable {
        public var version: String
        public var system: String
        public var install: String
        public var log: String
        public var platform = "ios"

        public init(version: String, system: String, install: String, log: String) {
            self.version = version; self.system = system; self.install = install; self.log = log
        }

        /** The body the admin takes (an empty note left out). */
        public func body(_ note: String) -> JSON {
            var o: [String: JSON] = [
                "platform": .string(platform),
                "version": .string(version),
                "system": .string(String(system.prefix(Report.mostSystem))),
                "log": .string(log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Report.noLog : log),
                "install": .string(install),
            ]
            let n = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Report.mostNote))
            if !n.isEmpty { o["note"] = .string(n) }
            return .object(o)
        }

        /** As shown in the sheet. */
        public func shown() -> String {
            "Version: \(version)\nInstall: iPhone / iPad\nSystem: \(system)\nInstall ID: \(install) (made once, at random)\n\n"
                + "The app's recent log (email addresses taken out):\n\n" + (log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty)" : log)
        }
    }

    /** A random id made once for this install (no personal data). */
    public static func installId(_ defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: "report.install"), id.count == 36 { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: "report.install")
        return id
    }

    /** Email addresses → "(email)". */
    public static func scrub(_ text: String) -> String {
        text.replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+"#, with: "(email)", options: .regularExpression)
    }

    /** The last [most] UTF-8 bytes of [text] (a song title in Japanese takes 3 a letter), starting at a whole line. */
    public static func newest(_ text: String, _ most: Int) -> String {
        let bytes = Array(text.utf8)
        if bytes.count <= most { return text }
        var from = bytes.count - most
        while from < bytes.count, bytes[from] & 0xC0 == 0x80 { from += 1 } // not inside a letter
        let tail = String(decoding: bytes[from...], as: UTF8.self)
        guard let nl = tail.firstIndex(of: "\n") else { return tail }
        return String(tail[tail.index(after: nl)...])
    }

    /** Sends [body] (What.body): the report's code to quote ("RM-0123"). */
    public static func send(_ body: JSON, to base: String = admin) async throws -> String {
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/music/reports") else { throw Plain("That didn't go through. Try again.") }
        var r = URLRequest(url: url, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.httpBody = body.data()
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("RadianceMusic-iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Http.send(r)
        return try answer(response.statusCode, data, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }

    /** The admin's answer: the code, or what it said no to in plain words. */
    static func answer(_ code: Int, _ data: Data, retryAfter: String?, now: Date = Date()) throws -> String {
        let j = JSON.parse(data)
        if (200..<300).contains(code) {
            if let c = j?["code"]?.string, !c.isEmpty { return c }
            if let id = j?["id"]?.int64, id > 0 { return String(format: "RM-%04lld", id) }
            return "sent"
        }
        let message = j?["message"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        switch code {
        case 422: throw Plain(message ?? "Check what you wrote, then send it again.", "422")
        case 413: throw Plain(message ?? "That's too long to send: make it shorter and send again.", "413")
        case 429: throw Plain("Too many tries just now. \(tryAgain(waitSeconds(retryAfter, now: now)))", "429")
        case 503: throw Plain("Radiance Music's site isn't taking these right now. Try again later, or email hello@radianceph.com.", "503 reports off")
        case 500...599: throw Plain("Radiance Music's site isn't answering right now. Try again in a few minutes.", "HTTP \(code)")
        default: throw Plain(message ?? "That didn't go through. Try again.", "HTTP \(code)")
        }
    }

    /** Retry-After in seconds, either as seconds or as a date; nil if it's not there (or not readable). */
    static func waitSeconds(_ header: String?, now: Date) -> Int? {
        guard let h = header?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
        if let s = Int(h) { return max(s, 0) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let at = f.date(from: h) else { return nil }
        return max(Int(ceil(at.timeIntervalSince(now))), 0)
    }

    /** When to try again, in plain words ("Try again in 3 minutes."). */
    static func tryAgain(_ seconds: Int?) -> String {
        guard let s = seconds else { return "Try again in a few minutes." }
        if s <= 60 { return "Try again in a minute." }
        if s < 3600 { return "Try again in \((s + 59) / 60) minutes." }
        let h = (s + 3599) / 3600
        return h == 1 ? "Try again in an hour." : "Try again in \(h) hours."
    }
}
