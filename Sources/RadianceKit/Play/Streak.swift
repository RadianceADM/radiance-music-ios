import Foundation

/**
 * Songs that wouldn't play, one after another (Android's play/Streak.kt): each is skipped to the next, but the third
 * in a row stops the music (no connection mustn't run through the whole queue in a few seconds). A song that plays,
 * or one you pick, starts the count again; a song you retry that still won't play stops there.
 */
public struct Streak: Sendable {
    public enum Then: Sendable {
        /** On to the next song. */
        case next
        /** Stop here (no next song, or you retried this one). */
        case stop
        /** Stop: too many in a row. */
        case tooMany
    }

    public static let most = 3
    let most: Int
    /** Songs that wouldn't play, in a row. */
    public private(set) var inARow = 0
    private var retrying = false

    public init(most: Int = Streak.most) { self.most = most }

    /** A song wouldn't play ([hasNext]: there's a song after it): what to do. */
    public mutating func failed(hasNext: Bool) -> Then {
        inARow += 1
        let then: Then
        if retrying { then = .stop } else if inARow >= most { then = .tooMany } else if !hasNext { then = .stop } else { then = .next }
        retrying = false
        return then
    }

    /** A song plays: all's well again. */
    public mutating func played() { inARow = 0; retrying = false }

    /** You picked a song (or the next one): a fresh start. */
    public mutating func picked() { played() }

    /** You asked for this song again: if it still won't play, it stops there (no skipping on). */
    public mutating func retry() { retrying = true }
}
