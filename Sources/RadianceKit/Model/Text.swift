import Foundation

// Text the way the Android app (model/Track.kt) and the computer app compare it: accents, case, spaces and
// bracketed extras aside. Kept to the same rules so a song filed on one is found on the other.

extension Unicode.Scalar {
    /** A letter or a decimal digit (Kotlin's Char.isLetterOrDigit). */
    var isLetterOrDigit: Bool {
        switch properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber: return true
        default: return false
        }
    }

    var isWhitespaceLike: Bool { properties.isWhitespace }
}

extension String {
    /** Only the letters and digits. */
    var lettersAndDigits: String {
        var s = String.UnicodeScalarView()
        for u in unicodeScalars where u.isLetterOrDigit { s.append(u) }
        return String(s)
    }
}

/** Accents aside: "Ñino" -> "Nino". */
public func fold(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    for u in text.decomposedStringWithCanonicalMapping.unicodeScalars where u.properties.generalCategory != .nonspacingMark {
        out.append(u)
    }
    return String(out)
}

/** Lowercase letters and digits only, without bracketed extras ("(Remastered)"). */
public func plain(_ text: String) -> String {
    var depth = 0
    var out = ""
    for u in fold(text).unicodeScalars {
        switch u {
        case "(", "[": depth += 1
        case ")", "]": depth = max(depth - 1, 0)
        default:
            if depth == 0 && u.isLetterOrDigit { out += String(u).lowercased() }
        }
    }
    return out
}

/** Every word typed is in the song's title, artist or album (accents, case and spaces aside). */
public func matches(_ t: Track, _ query: String) -> Bool {
    let hay = fold("\(t.title) \(t.artist) \(t.album)").lowercased()
    let joined = hay.lettersAndDigits
    return words(fold(query).lowercased()).allSatisfy { w in
        let word = w.lettersAndDigits
        return word.isEmpty || hay.contains(word) || joined.contains(word)
    }
}

/** 245 -> "4:05". */
public func clock(_ seconds: Int) -> String {
    let s = max(seconds, 0)
    return String(format: "%d:%02d", s / 60, s % 60)
}

/** "A feat. B & C, D" -> [A, B, C, D]. */
public func splitCredit(_ credit: String) -> [String] {
    var parts = [credit]
    for sep in [" feat. ", " ft. ", " featuring ", " with ", " x ", " X ", " & ", ", ", " and "] {
        parts = parts.flatMap { $0.components(separatedBy: sep) }
    }
    return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}

/** The text split at runs of white space (Kotlin's split(Regex("\\s+")), empty pieces dropped). */
func words(_ text: String) -> [String] {
    text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
}

/** "4:05", "1:02:03" or "245.3" -> seconds. */
func parseClock(_ text: String) -> Int {
    let t = text.trimmingCharacters(in: .whitespaces)
    if t.isEmpty { return 0 }
    if t.contains(":") {
        return t.split(separator: ":", omittingEmptySubsequences: false).reduce(0) { acc, part in
            acc * 60 + (Double(part.trimmingCharacters(in: .whitespaces)).map { Int($0) } ?? 0)
        }
    }
    return Double(t).map { Int($0) } ?? 0
}
