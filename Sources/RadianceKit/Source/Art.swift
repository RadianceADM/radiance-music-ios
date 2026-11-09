import Foundation

/**
 * Covers at the size they're shown (android#36; owner, 2026-11-08: "ang low quality ng album art"). YouTube Music's
 * search offers a song's cover at 60 and 120 px only; its image server keeps the original (1400 px for most albums) and
 * gives any size the address asks for (…=w1200-h1200-l90-rj). So a row asks for a small one, Now Playing, the saved
 * cover and the story for a big one.
 */
public enum Art {
    /** Now Playing's, the saved cover's, the story's: sharp on any screen, a few hundred KB. */
    public static let big = 1200
    /** The lock screen's. */
    public static let medium = 544
    /** The steps asked for, so one cover is fetched (and kept) once per step, not once per pixel size. */
    static let steps = [120, 226, medium, big]

    /** Whether a bigger copy of [url] can be asked for (YouTube Music's covers). */
    public static func grows(_ url: String) -> Bool {
        url.range(of: #"^https://(lh\d|yt\d)\.(googleusercontent|ggpht)\.com/"#, options: .regularExpression) != nil
    }

    /** [url] asking for at least [px] across (rounded up to a step, at most [big]); any other address as it is. */
    public static func sized(_ url: String, _ px: Int) -> String {
        guard grows(url) else { return url }
        let want = steps.first { $0 >= px } ?? big
        // the size part at the end: "=w120-h120-l90-rj", "=s120-c-k-c0x00ffffff-no-rj"
        let base = url.range(of: #"=[a-z][^/=]*$"#, options: .regularExpression).map { String(url[..<$0.lowerBound]) } ?? url
        return "\(base)=w\(want)-h\(want)-l90-rj"
    }
}
