import SwiftUI

/**
 * A party's reactions as small soft pictures, the same as the server's party page and Android draw them (Android's
 * ui/Reactions.kt): round faces, a rounded flame, a heart, clapping hands, a balloon (owner: nothing spiky; no emoji
 * font needed). The server carries the emoji itself; one this iPhone doesn't know shows as the emoji's text.
 */
enum Reactions {
    struct Pic {
        let emoji: String
        let name: String
        let draw: (inout GraphicsContext) -> Void
    }

    private static let face = Color(hex: 0xFFC94D)
    private static let ink = Color(hex: 0x5A3A12)

    private static let flame = SVGPath.parse("M12 21.5c-3.9 0-6.6-2.7-6.6-6.3 0-2.5 1.3-4.4 2.8-5.9.3 1.6 1.1 2.6 2.1 3-.4-3.1.9-6.2 3-8.2.5 2.4 1.9 4.2 3.3 5.8 1.2 1.4 1.9 3.1 1.9 5 0 3.9-2.7 6.6-6.5 6.6z")
    private static let flameCore = SVGPath.parse("M12 20.2c-1.8 0-3-1.2-3-2.9 0-1.5 1-2.6 2.2-3.5.1.9.6 1.5 1.3 1.7.1-1.2.6-2.1 1.4-2.8.6 1 1 2 1 3.3 0 2.5-1.2 4.2-2.9 4.2z")
    private static let heart = SVGPath.parse("M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z")
    private static let laughEyes = SVGPath.parse("M7.3 9.8q1.6-1.8 3.2 0M13.5 9.8q1.6-1.8 3.2 0")
    private static let laughMouth = SVGPath.parse("M7 13.2h10a5 5 0 0 1-10 0z")
    private static let clapLines = SVGPath.parse("M4.2 5.2q.6-1.5 2-2M19.8 3.2q1.3.5 1.8 1.9M20.8 8.1q.8.3 1.1 1")
    private static let knot = SVGPath.parse("M10.9 17.1h2.2l-1.1 1.5z")
    private static let string = SVGPath.parse("M12 18.6c-1.4 1 1.4 1.8 0 3.2")
    private static let brows = SVGPath.parse("M6.8 7.3q1.6-1.2 3.2-.6M14 6.7q1.6-.6 3.2.6")

    /** The six on the party's screen, in its order (on a 24 × 24 grid). */
    static let all: [Pic] = [
        Pic(emoji: "🔥", name: "Fire") { c in
            fill(&c, flame, Color(hex: 0xF38A35), 1.8)
            fill(&c, flameCore, Color(hex: 0xFFD27A), 1)
        },
        Pic(emoji: "❤️", name: "Love") { c in
            fill(&c, heart, Color(hex: 0xF2685B), 1.6)
            var r = turned(c, -30, CGPoint(x: 7.3, y: 7.6))
            oval(&r, 7.3, 7.6, 1.6, 1.1, .white, 0.35)
        },
        Pic(emoji: "😂", name: "Laugh") { c in
            oval(&c, 12, 12, 10, 10, face)
            line(&c, laughEyes, ink, 1.6)
            fill(&c, laughMouth, ink, 1.2)
            oval(&c, 12, 16.7, 2.4, 1.2, Color(hex: 0xF2685B))
        },
        Pic(emoji: "👏", name: "Clap") { c in
            var a = turned(c, -16, CGPoint(x: 9, y: 13))
            a.fill(Path(roundedRect: CGRect(x: 5.5, y: 6.5, width: 7, height: 13), cornerRadius: 3.5), with: .color(Color(hex: 0xFFB774)))
            var b = turned(c, 16, CGPoint(x: 15, y: 12))
            b.fill(Path(roundedRect: CGRect(x: 11.5, y: 5.5, width: 7, height: 13), cornerRadius: 3.5), with: .color(Color(hex: 0xF38A35)))
            line(&c, clapLines, Color(hex: 0xFFD27A), 1.6)
        },
        Pic(emoji: "🎉", name: "Party") { c in
            oval(&c, 12, 9.6, 6.4, 7.4, Color(hex: 0xE2558A))
            var shine = turned(c, 20, CGPoint(x: 9.6, y: 7))
            oval(&shine, 9.6, 7, 1.5, 2.4, .white, 0.3)
            fill(&c, knot, Color(hex: 0xE2558A), 1)
            line(&c, string, Color(hex: 0xF5F5F4), 1.3, 0.75)
            oval(&c, 4, 5, 1.2, 1.2, Color(hex: 0xFFD27A))
            oval(&c, 20.2, 4.2, 1, 1, Color(hex: 0xF38A35))
            oval(&c, 19.6, 16.5, 1.1, 1.1, Color(hex: 0x9BD39B))
        },
        Pic(emoji: "😮", name: "Wow") { c in
            oval(&c, 12, 12, 10, 10, face)
            line(&c, brows, ink, 1.4)
            oval(&c, 8.7, 10.2, 1.4, 1.4, ink)
            oval(&c, 15.3, 10.2, 1.4, 1.4, ink)
            oval(&c, 12, 15.6, 2.4, 2.9, ink)
        },
    ]

    /** [emoji]'s picture (with or without its colour selector, as "❤" and "❤️"), or nil. */
    static func of(_ emoji: String) -> Pic? {
        let bare = emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
        return all.first { $0.emoji.replacingOccurrences(of: "\u{FE0F}", with: "") == bare }
    }

    private static func fill(_ c: inout GraphicsContext, _ p: Path, _ color: Color, _ stroke: CGFloat = 0) {
        c.fill(p, with: .color(color))
        if stroke > 0 { c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)) }
    }

    private static func line(_ c: inout GraphicsContext, _ p: Path, _ color: Color, _ width: CGFloat, _ alpha: Double = 1) {
        c.stroke(p, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private static func oval(_ c: inout GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color, _ alpha: Double = 1) {
        c.fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)), with: .color(color.opacity(alpha)))
    }

    /** [c] turned [degrees] around [p]. */
    private static func turned(_ c: GraphicsContext, _ degrees: Double, _ p: CGPoint) -> GraphicsContext {
        var r = c
        r.translateBy(x: p.x, y: p.y)
        r.rotate(by: .degrees(degrees))
        r.translateBy(x: -p.x, y: -p.y)
        return r
    }
}

/** A reaction drawn at [size]: its soft picture, or its emoji as text when it isn't one of the six. */
struct ReactionIcon: View {
    let emoji: String
    let size: CGFloat

    var body: some View {
        if let pic = Reactions.of(emoji) {
            Canvas { c, s in
                var c = c
                c.scaleBy(x: s.width / 24, y: s.height / 24)
                pic.draw(&c)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(pic.name)
        } else {
            Text(emoji).font(.system(size: size * 0.55)).frame(width: size, height: size)
        }
    }
}

/**
 * An SVG path's words as a Path (the reactions' pictures, as Android parses them): M L H V C Q A Z and their small
 * letters, numbers run together as SVG allows ("-.4-3.1.9"); arcs here are round ones (as all of these are).
 */
enum SVGPath {
    static func parse(_ d: String) -> Path {
        let t = tokens(d)
        var p = Path()
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero
        var start = CGPoint.zero
        func isNumber(_ k: Int) -> Bool { k < t.count && t[k].number != nil }
        func num() -> CGFloat { defer { i += 1 }; return t[i].number ?? 0 }
        while i < t.count {
            if let c = t[i].command { cmd = c; i += 1 }
            let rel = cmd.isLowercase
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
            switch Character(cmd.lowercased()) {
            case "z":
                p.closeSubpath()
                cur = start
                while isNumber(i) { i += 1 } // nothing follows a close
                continue
            default:
                guard isNumber(i) else { continue }
            }
            switch Character(cmd.lowercased()) {
            case "m":
                let q = at(num(), num())
                p.move(to: q)
                cur = q
                start = q
                cmd = rel ? "l" : "L" // more numbers after a move are lines
            case "l":
                let q = at(num(), num())
                p.addLine(to: q)
                cur = q
            case "h":
                let x = num()
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                p.addLine(to: cur)
            case "v":
                let y = num()
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                p.addLine(to: cur)
            case "c":
                let c1 = at(num(), num()), c2 = at(num(), num()), q = at(num(), num())
                p.addCurve(to: q, control1: c1, control2: c2)
                cur = q
            case "q":
                let c1 = at(num(), num()), q = at(num(), num())
                p.addQuadCurve(to: q, control: c1)
                cur = q
            case "a":
                let r = num()
                i += 2 // the second radius (the same: round arcs) and the turn (none)
                let large = num() != 0
                let sweep = num() != 0
                let q = at(num(), num())
                arc(&p, from: cur, to: q, r: r, large: large, sweep: sweep)
                cur = q
            default:
                i += 1 // a letter it doesn't know: passed over
            }
        }
        return p
    }

    /** A round arc from [a] to [b] (SVG's endpoint form), drawn as cubic curves of a quarter turn at most. */
    static func arc(_ p: inout Path, from a: CGPoint, to b: CGPoint, r: CGFloat, large: Bool, sweep: Bool) {
        guard r > 0, a != b else { return p.addLine(to: b) }
        let x1 = (a.x - b.x) / 2, y1 = (a.y - b.y) / 2
        let d2 = x1 * x1 + y1 * y1
        let radius = max(r, sqrt(d2))
        let k = sqrt(max(0, (radius * radius - d2) / d2)) * (large == sweep ? -1 : 1)
        let cx = k * y1 + (a.x + b.x) / 2, cy = -k * x1 + (a.y + b.y) / 2
        let t1 = atan2(a.y - cy, a.x - cx)
        var dt = atan2(b.y - cy, b.x - cx) - t1
        if sweep, dt < 0 { dt += 2 * .pi }
        if !sweep, dt > 0 { dt -= 2 * .pi }
        let parts = max(1, Int(ceil(abs(dt) / (.pi / 2))))
        let step = dt / CGFloat(parts)
        let h = 4 / 3 * tan(step / 4)
        var t = t1
        for _ in 0..<parts {
            let t2 = t + step
            let p1 = CGPoint(x: cx + radius * cos(t), y: cy + radius * sin(t))
            let p2 = CGPoint(x: cx + radius * cos(t2), y: cy + radius * sin(t2))
            let c1 = CGPoint(x: p1.x - h * radius * sin(t), y: p1.y + h * radius * cos(t))
            let c2 = CGPoint(x: p2.x + h * radius * sin(t2), y: p2.y - h * radius * cos(t2))
            p.addCurve(to: p2, control1: c1, control2: c2)
            t = t2
        }
    }

    private enum Token {
        case command(Character), number(CGFloat)
        var command: Character? { if case .command(let c) = self { return c }; return nil }
        var number: CGFloat? { if case .number(let n) = self { return n }; return nil }
    }

    private static func tokens(_ d: String) -> [Token] {
        var out: [Token] = []
        var n = ""
        func flush() {
            if let v = Double(n) { out.append(.number(CGFloat(v))) }
            n = ""
        }
        for ch in d {
            if ch.isLetter, ch != "e" {
                flush()
                out.append(.command(ch))
            } else if ch == "-" {
                // a minus starts a number (unless it's an exponent's)
                if n.hasSuffix("e") { n.append(ch) } else { flush(); n = "-" }
            } else if ch == "." {
                // a second dot starts the next number (".5.5" is 0.5 and 0.5)
                if n.contains(".") && !n.contains("e") { flush() }
                n.append(ch)
            } else if ch.isNumber || ch == "e" {
                n.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return out
    }
}
