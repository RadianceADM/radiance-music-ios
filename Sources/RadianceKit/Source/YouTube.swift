import Foundation

/**
 * YouTube Music, the fallback when the Internet Archive doesn't have a song (Android's source/YouTube.kt): search,
 * suggestions, "Up next" and lyrics, asked as the YouTube Music website asks them. Its songs' sound comes from your
 * Radiance Music Server (radiance-music#73), never from YouTube to the iPhone.
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
    // The iPhone never fetches a YouTube song's sound itself: its Radiance Music Server gets it (owner, 2026-11-09:
    // "if not yet exists in server download from youtube"; radiance-music#73), and the iPhone plays the server's copy.

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
