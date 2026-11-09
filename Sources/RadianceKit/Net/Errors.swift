import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 * What went wrong, as a short sentence anyone understands (Android's net/Errors.kt): never an error's own text
 * ("The Internet connection appears to be offline.", "NSURLErrorDomain -1009"). The app's own words ([Plain]) come
 * through as they are.
 */
public enum Errors {
    public static let offline = "You're offline."
    public static let slow = "The connection is too slow right now."
    public static let connect = "Couldn't connect. Check your Wi-Fi or mobile data."
    public static let dropped = "The connection dropped. Try again."
    public static let safe = "Couldn't connect safely. If this Wi-Fi has a sign-in page, sign in first."
    public static let full = "Your iPhone is full. Free up some space and try again."
    public static let gone = "The file isn't on this iPhone any more."
    public static let robot = "YouTube wants to check you're not a robot. Try again in a few minutes."
    public static let country = "This song isn't available in your country."
    public static let adults = "YouTube keeps this song for signed-in adults, so it can't play here."
    public static let unavailable = "This song isn't available on YouTube."
    public static let youtube = "YouTube didn't answer as expected. Try again later."
    public static let stopped = "Stopped."
    public static let something = "Something went wrong. Try again."

    /** [e] in plain words. [online]: whether the phone has internet now (then a connection problem is "You're offline"). */
    public static func say(_ e: Error?, online: Bool = true) -> String {
        guard let e else { return something }
        if !online && network(e) { return offline }
        if let p = e as? Plain { return p.words }
        if let y = e as? YouTubeRefused { return y.words }
        if e is CancellationError { return stopped }
        if let u = e as? URLError { return url(u) }
        let ns = e as NSError
        if ns.domain == NSURLErrorDomain { return url(URLError(code(ns.code))) }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 28 { return full } // ENOSPC
        if ns.domain == NSCocoaErrorDomain {
            if ns.code == NSFileWriteOutOfSpaceError { return full }
            if ns.code == NSFileNoSuchFileError || ns.code == NSFileReadNoSuchFileError { return gone }
        }
        if e is HTTPStatus { return youtube }
        return something
    }

    /** A connection problem (no network, too slow, dropped), not the phone's or the song's. */
    public static func network(_ e: Error) -> Bool {
        if let u = e as? URLError { return url(u) != something }
        return (e as NSError).domain == NSURLErrorDomain
    }

    static func url(_ u: URLError) -> String {
        switch u.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost, .dnsLookupFailed: return offline
        case .timedOut: return slow
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected, .appTransportSecurityRequiresSecureConnection: return safe
        case .cannotConnectToHost: return connect
        case .networkConnectionLost: return dropped
        case .cancelled: return stopped
        default: return something
        }
    }
}

/** YouTube said no to a song, with its reason in plain words. */
public struct YouTubeRefused: Error, CustomStringConvertible {
    public let words: String
    public let status: String
    public var description: String { "\(words) (\(status))" }
}

/** An NSURLErrorDomain code as a URLError's (Linux's Foundation can say "no such code"). */
func code(_ raw: Int) -> URLError.Code {
    let c: URLError.Code? = URLError.Code(rawValue: raw)
    return c ?? .unknown
}
