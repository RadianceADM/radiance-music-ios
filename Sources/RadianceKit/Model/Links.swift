import Foundation

/** Where to hear a song, and where to reach us (Android's Share.link and About). */
public enum Links {
    /** Radiance Music's own page. */
    public static let site = "https://music.radianceph.com"
    public static let email = "hello@radianceph.com"

    /** Where others can hear [t]: YouTube Music, or the Internet Archive's page for it. */
    public static func song(_ t: Track) -> String {
        switch t.source {
        case .youtube:
            return "https://music.youtube.com/watch?v=\(t.id)"
        case .archive:
            guard let r = t.id.range(of: #"archive\.org/download/([^/]+)"#, options: .regularExpression) else { return t.id }
            let item = t.id[r].replacingOccurrences(of: "archive.org/download/", with: "")
            return "https://archive.org/details/\(item)"
        case .server:
            // a server's songs are only for the friends it invited: the song looked up on YouTube Music instead
            let words = "\(t.artist) \(t.title)".trimmingCharacters(in: .whitespaces)
            return "https://music.youtube.com/search?q=" + (words.addingPercentEncoding(withAllowedCharacters: query) ?? "")
        }
    }

    /** What apps that take words get: the song and where to hear it. */
    public static func text(_ t: Track) -> String { "\(t.title) — \(t.artist)\n\(song(t))" }

    /** An email to us, its subject saying which app and version. */
    public static func mail(version: String) -> String {
        let subject = "Radiance Music \(version) (iPhone)".addingPercentEncoding(withAllowedCharacters: query) ?? ""
        return "mailto:\(email)?subject=\(subject)"
    }

    /** Letters, digits and -._~ stay; the rest (spaces, &, +, =) is written as %XX. */
    private static let query = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

/** The changelog that comes with the app, read for What's New (Android's About). */
public enum Changelog {
    public struct Release: Equatable, Sendable {
        public let version: String
        public let items: [String]
    }

    /** Its versions, newest first, each with its items (a wrapped line joins its item). */
    public static func releases(_ text: String) -> [Release] {
        var out: [Release] = []
        var version: String?
        var items: [String] = []
        func flush() {
            if let version { out.append(Release(version: version, items: items)) }
            items = []
        }
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                flush()
                version = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("- ") {
                items.append(String(t.dropFirst(2)))
            } else if !t.isEmpty, line.hasPrefix(" "), !items.isEmpty {
                items[items.count - 1] += " " + t
            }
        }
        flush()
        return out
    }
}
