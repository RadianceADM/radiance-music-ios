import Foundation

/**
 * YouTube Music, the fallback when the Internet Archive doesn't have a song (Android's source/YouTube.kt). Android
 * finds the sound through NewPipe; an iPhone app can't run that, so this asks YouTube's own apps' API (innertube)
 * directly: search and "Up next" as the YouTube Music website does, and the sound as YouTube's iPhone app does, whose
 * answer has plain AAC (.m4a) addresses that the iPhone's player opens as they are (it can't play WebM/Opus).
 */
public enum YouTube {
    /** The website's client (search, suggestions, Up next, lyrics). */
    static let webVersion = "1.20251020.01.00"
    static var web: JSON { ["client": ["clientName": "WEB_REMIX", "clientVersion": .string(webVersion), "hl": "en"]] }
    static let webHeaders = ["Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/"]
    static let api = "https://music.youtube.com/youtubei/v1/"
    /** YouTube Music's "Songs" filter (songs only: no music videos, phones have none). */
    static let songsOnly = "EgWKAQIIAWoKEAkQBRAKEAMQBA=="

    // MARK: - search

    /** Songs for [query]. */
    public static func search(_ query: String) async throws -> [Track] {
        let r = try await Http.postJson(api + "search?prettyPrint=false", ["context": web, "query": .string(query), "params": .string(songsOnly)], headers: webHeaders)
        return songs(r)
    }

    /** The songs in a search answer (each list row that plays a song). */
    public static func songs(_ answer: JSON) -> [Track] {
        var seen = Set<String>()
        return answer.collect("musicResponsiveListItemRenderer").compactMap(row).filter { seen.insert($0.id).inserted }
    }

    /** One row: its song, its artists, album and length (the second column: "Artist • Album • 3:08"). */
    static func row(_ r: JSON) -> Track? {
        guard let id = r["playlistItemData"]?["videoId"]?.string
                ?? r["overlay"]?.collect("watchEndpoint").first?["videoId"]?.string
                ?? r["flexColumns"]?[0]?.collect("watchEndpoint").first?["videoId"]?.string,
              !id.isEmpty else { return nil }
        // a song, not a music video (only songs: phones have none)
        let type = r.collect("musicVideoType").first?.string
        if let type, type != "MUSIC_VIDEO_TYPE_ATV" && type != "MUSIC_VIDEO_TYPE_PRIVATELY_OWNED_TRACK" { return nil }
        let columns = r["flexColumns"]?.array ?? []
        func runs(_ i: Int) -> [JSON] { columns.count > i ? (columns[i]["musicResponsiveListItemFlexColumnRenderer"]?["text"]?["runs"]?.array ?? []) : [] }
        let title = runs(0).compactMap { $0["text"]?.string }.joined()
        guard !title.isEmpty else { return nil }
        let (artist, album, seconds) = byline(runs(1))
        let thumbs = r["thumbnail"]?["musicThumbnailRenderer"]?["thumbnail"]?["thumbnails"]?.array ?? []
        let art = thumbs.max { ($0["height"]?.int ?? 0) < ($1["height"]?.int ?? 0) }?["url"]?.string ?? ""
        return Track(source: .youtube, id: id, title: title, artist: artist, album: album, seconds: seconds, art: art, format: "AAC")
    }

    /**
     * "Artist & Artist • Album • 3:08" as its parts: the runs before the first " • " are the artists (as NewPipe's
     * uploader name), a run that opens an album page is the album, one like "3:08" the length.
     */
    static func byline(_ runs: [JSON]) -> (String, String, Int) {
        var artist = ""
        var album = ""
        var seconds = 0
        var part = 0
        for run in runs {
            let text = run["text"]?.string ?? ""
            if text == " • " || text == " \u{2022} " { part += 1; continue }
            let page = run.collect("pageType").first?.string
            if page == "MUSIC_PAGE_TYPE_ALBUM" { album = text; continue }
            if text.range(of: #"^\d+(:\d{2})+$"#, options: .regularExpression) != nil { seconds = parseClock(text); continue }
            if part == 0 { artist += text }
        }
        if artist.hasSuffix(" - Topic") { artist.removeLast(8) }
        return (artist.trimmingCharacters(in: .whitespaces), album, seconds)
    }

    public static func suggestions(_ query: String) async -> [String] {
        guard let r = try? await Http.postJson(api + "music/get_search_suggestions?prettyPrint=false", ["context": web, "input": .string(query)], headers: webHeaders) else { return [] }
        return suggestionsIn(r)
    }

    static func suggestionsIn(_ r: JSON) -> [String] {
        r.collect("searchSuggestionRenderer").compactMap { s in
            let text = (s["suggestion"]?["runs"]?.array ?? []).compactMap { $0["text"]?.string }.joined()
            return text.isEmpty ? nil : text
        }
    }

    // MARK: - the sound

    /** A stream to play or save: its address, file ending and size (if known). */
    public struct Stream: Sendable, Equatable {
        public let url: String
        public let mime: String
        public let ext: String
        public let size: Int64?
        public let kbps: Int
        /** The headers to fetch it with (the client it came from). */
        public let headers: [String: String]
    }

    /** One of YouTube's own apps, as the player asks it. */
    struct Client: Sendable {
        let name: String
        let id: Int
        let version: String
        let userAgent: String
        let extra: [String: JSON]
    }

    /** Tried in turn: the iPhone app's answer has plain addresses; the headset app's is the spare. */
    static let clients: [Client] = [
        Client(name: "IOS", id: 5, version: "20.10.4",
               userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
               extra: ["deviceMake": "Apple", "deviceModel": "iPhone16,2", "osName": "iPhone", "osVersion": "18.3.2.22D82"]),
        Client(name: "ANDROID_VR", id: 28, version: "1.65.10",
               userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
               extra: ["deviceMake": "Oculus", "deviceModel": "Quest 3", "androidSdkVersion": 32, "osName": "Android", "osVersion": "12L"]),
    ]

    private static let cache = StreamCache()

    /**
     * The song's AAC sound (the best the iPhone plays: 128 kbps, sometimes 256). Kept for two hours (YouTube's
     * addresses last about six).
     *
     * NOT SETTLED (2026-11-09): this first try gets only the first ~1 MB of a song (YouTube wants a token from its own
     * apps for the rest). How the iPhone gets YouTube's sound is the owner's call; nothing plays from here until then.
     */
    public static func audio(_ id: String) async throws -> Stream {
        if let s = await cache.get(id) { return s }
        var refusal: Error?
        for c in clients {
            do {
                let s = try await audio(id, c)
                await cache.put(id, s)
                return s
            } catch let e as YouTubeRefused {
                refusal = refusal ?? e
            } catch {
                if Errors.network(error) { throw error }
                refusal = refusal ?? error
            }
        }
        throw refusal ?? Plain(Errors.youtube)
    }

    static func audio(_ id: String, _ c: Client) async throws -> Stream {
        var client: [String: JSON] = ["clientName": .string(c.name), "clientVersion": .string(c.version), "hl": "en", "gl": "US"]
        c.extra.forEach { client[$0] = $1 }
        let body: JSON = ["context": ["client": .object(client)], "videoId": .string(id), "contentCheckOk": true, "racyCheckOk": true]
        let r = try await Http.postJson("https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false", body, headers: [
            "User-Agent": c.userAgent, "X-YouTube-Client-Name": "\(c.id)", "X-YouTube-Client-Version": c.version,
        ])
        return try stream(r, userAgent: c.userAgent)
    }

    /** The best AAC stream in a player answer, or why there's none, in plain words. */
    static func stream(_ r: JSON, userAgent: String) throws -> Stream {
        let status = r["playabilityStatus"]?["status"]?.string ?? ""
        if status != "OK" {
            let reason = (r["playabilityStatus"]?["reason"]?.string ?? "").lowercased()
            let words: String
            switch true {
            // "Sign in to confirm your age" before "Sign in to confirm you're not a bot"
            case reason.contains("your age"), reason.contains("age-restricted"), reason.contains("inappropriate"): words = Errors.adults
            case reason.contains("bot"), reason.contains("sign in to confirm"): words = Errors.robot
            case reason.contains("country"), reason.contains("region"): words = Errors.country
            case status == "UNPLAYABLE", status == "ERROR": words = Errors.unavailable
            default: words = Errors.youtube
            }
            throw YouTubeRefused(words: words, status: "\(status): \(reason)")
        }
        let formats = (r["streamingData"]?["adaptiveFormats"]?.array ?? []).filter {
            ($0["mimeType"]?.string ?? "").hasPrefix("audio/mp4") && ($0["url"]?.string ?? "").hasPrefix("https://")
        }
        guard let best = formats.max(by: { ($0["bitrate"]?.int ?? 0) < ($1["bitrate"]?.int ?? 0) }) else {
            throw YouTubeRefused(words: "YouTube didn't give this song's sound.", status: "no AAC stream")
        }
        return Stream(url: best["url"]!.string!, mime: "audio/mp4", ext: "m4a", size: best["contentLength"]?.int64,
                      kbps: (best["averageBitrate"]?.int ?? best["bitrate"]?.int ?? 0) / 1000, headers: ["User-Agent": userAgent])
    }

    // MARK: - lyrics

    /** The text YouTube Music shows in its Lyrics tab (from LyricFind and others). */
    public static func lyrics(_ id: String) async -> String? {
        guard let next = try? await Http.postJson(api + "next?prettyPrint=false", ["context": web, "videoId": .string(id)], headers: webHeaders) else { return nil }
        guard let tab = next.collect("browseEndpoint").compactMap({ $0["browseId"]?.string }).first(where: { $0.hasPrefix("MPLYt") }) else { return nil }
        guard let page = try? await Http.postJson(api + "browse?prettyPrint=false", ["context": web, "browseId": .string(tab)], headers: webHeaders) else { return nil }
        let runs = page.collect("musicDescriptionShelfRenderer").first?["description"]?["runs"]?.array ?? []
        let text = runs.compactMap { $0["text"]?.string }.joined()
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    // MARK: - up next

    /**
     * Songs like [id], as YouTube Music plays after it (its radio for the song: the "Up next" list), the song itself
     * left out. Owner, 2026-11-06: a song from search played the other search results next ("hindi related").
     */
    public static func related(_ id: String) async throws -> [Track] {
        let body: JSON = ["context": web, "videoId": .string(id), "playlistId": .string("RDAMVM\(id)"), "isAudioOnly": true]
        let next = try await Http.postJson(api + "next?prettyPrint=false", body, headers: webHeaders)
        var seen = Set<String>()
        return next.collect("playlistPanelVideoRenderer").compactMap(upNext).filter { $0.id != id && seen.insert($0.id).inserted }
    }

    /** One song of an "Up next" list. */
    static func upNext(_ r: JSON) -> Track? {
        guard let vid = r["videoId"]?.string, !vid.isEmpty else { return nil }
        func runs(_ key: String) -> [JSON]? { r[key]?["runs"]?.array }
        guard let title = runs("title")?.first?["text"]?.string, !title.isEmpty else { return nil }
        // "Artist • Album • 2019" (the artist's run first; more artists joined by " & " or ", ")
        let by = runs("longBylineText") ?? runs("shortBylineText") ?? []
        let artist = by.compactMap { $0["text"]?.string }.joined().components(separatedBy: " • ").first ?? ""
        var album = ""
        for run in by where run.collect("pageType").first?.string == "MUSIC_PAGE_TYPE_ALBUM" { album = run["text"]?.string ?? "" }
        let length = runs("lengthText")?.first?["text"]?.string ?? ""
        let seconds = length.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.reduce(0) { $0 * 60 + $1 }
        let thumbs = r["thumbnail"]?["thumbnails"]?.array ?? []
        var art = thumbs.max { ($0["height"]?.int ?? 0) < ($1["height"]?.int ?? 0) }?["url"]?.string ?? ""
        // a bigger cover than the list's thumbnail
        art = art.replacingOccurrences(of: #"=w\d+-h\d+"#, with: "=w544-h544", options: .regularExpression)
        return Track(source: .youtube, id: vid, title: title, artist: artist, album: album, seconds: seconds, art: art, format: "AAC")
    }
}

/** Streams found lately, by video id, for two hours. */
actor StreamCache {
    private var kept: [String: (YouTube.Stream, Date)] = [:]

    func get(_ id: String) -> YouTube.Stream? {
        guard let (s, at) = kept[id], Date().timeIntervalSince(at) < 2 * 3600 else { return nil }
        return s
    }

    func put(_ id: String, _ s: YouTube.Stream) {
        kept[id] = (s, Date())
        if kept.count > 200 { kept = kept.filter { Date().timeIntervalSince($0.value.1) < 2 * 3600 } }
    }
}
