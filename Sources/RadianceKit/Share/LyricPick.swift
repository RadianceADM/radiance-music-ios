import Foundation

/**
 * Picking lyric lines for a story (Android's ShareSheet pick() and stretch(), android#37): the lines picked are next
 * to each other and together at most [most] characters (as Spotify's cards).
 */
public enum LyricPick {
    public static let most = 150

    /**
     * A tap on line [i]: an end of the picked lines comes off; the line just before or after joins them (if the
     * characters allow); any other line starts again from it. What to say when it can't, else nil.
     */
    public static func tap(_ picked: inout [Int], _ i: Int, _ lengths: [Int], most: Int = most) -> String? {
        let sorted = picked.sorted()
        if picked.contains(i) {
            if i == sorted.first || i == sorted.last { picked.removeAll { $0 == i } }
            else { picked = [i] } // from the middle: just this one
            return nil
        }
        if picked.isEmpty || i == sorted.first! - 1 || i == sorted.last! + 1 {
            if picked.reduce(0, { $0 + lengths[$1] }) + lengths[i] > most {
                return picked.isEmpty ? "That line is longer than \(most) characters" : "\(most) characters at most"
            }
            picked.append(i)
            return nil
        }
        if lengths[i] > most { return "That line is longer than \(most) characters" }
        picked = [i]
        return nil
    }

    /**
     * Held at line [from] and slid to [to]: the lines from one to the other, as many as fit the [most] characters
     * counting from the line held. Second: whether the limit cut it short.
     */
    public static func stretch(_ from: Int, _ to: Int, _ lengths: [Int], most: Int = most) -> ([Int], Bool) {
        let step = to >= from ? 1 : -1
        var run = [from]
        var used = lengths[from]
        var at = from
        while at != to {
            at += step
            if used + lengths[at] > most { return (run.sorted(), true) }
            used += lengths[at]
            run.append(at)
        }
        return (run.sorted(), false)
    }
}
