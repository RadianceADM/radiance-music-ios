import os

/**
 * The app's own lines in the iPhone's log (Swift's print never gets there): "radiance-play: …", as Android logs them.
 * Read from the laptop with `pymobiledevice3 syslog live -pn RadianceMusic -m radiance-`; Report a Problem sends them.
 */
enum Log {
    private static let logger = Logger(subsystem: "io.github.radianceadm.music", category: "app")

    /** [area] is play, mix, split, party, share… */
    static func say(_ area: String, _ words: String) {
        logger.notice("radiance-\(area, privacy: .public): \(words, privacy: .public)")
    }
}
