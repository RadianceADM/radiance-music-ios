import RadianceKit
import SwiftUI

/**
 * The A to Z rail beside Liked Songs (Android's AzRail): tap a letter, or slide along it, to jump there (a big letter
 * shows where you are); letters with no songs stay faint, and the letter of the songs at the top is lit.
 */
struct AzRail: View {
    /** Where each letter's songs start (Library.firsts). */
    let firsts: [Character: Int]
    /** The letter of the song at the top of the list. */
    let lit: Character?
    let height: CGFloat
    @Binding var held: Character?
    let jump: (Int) -> Void

    /** Its height: the letters at their full size, and the least they can shrink to. */
    static let most: CGFloat = 15 * CGFloat(Library.rail.count) + 12
    static let least: CGFloat = 9 * CGFloat(Library.rail.count) + 12

    var body: some View {
        let each = (height - 12) / CGFloat(Library.rail.count)
        let shown = held ?? lit
        VStack(spacing: 0) {
            ForEach(Library.rail, id: \.self) { c in
                Text(String(c))
                    .font(.system(size: min(11, each * 0.75), weight: .heavy))
                    .foregroundStyle(c == shown ? Color.black : firsts[c] != nil ? Brand.orange : Brand.orange.opacity(0.28))
                    .frame(width: 20, height: each)
                    .background(c == shown ? Brand.orange : Color.clear, in: Circle())
            }
        }
        .padding(.vertical, 6)
        .frame(width: 26, height: height)
        .background(Color.white.opacity(held != nil ? 0.1 : 0.04), in: Capsule())
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { pick(at: $0.location.y) }
                .onEnded { _ in held = nil }
        )
        .sensoryFeedback(.selection, trigger: held) { _, now in now != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A to Z")
        .accessibilityValue(lit.map { String($0) } ?? "")
        .accessibilityAdjustableAction { way in step(way == .increment ? 1 : -1) }
    }

    private func pick(at y: CGFloat) {
        let i = min(max(Int(y / height * CGFloat(Library.rail.count)), 0), Library.rail.count - 1)
        let letter = Library.rail[i]
        if letter == held { return }
        held = letter
        if let at = Library.jump(firsts, i) { jump(at) }
    }

    /** VoiceOver: swipe up or down for the next or the last letter that has songs. */
    private func step(_ by: Int) {
        let from = lit.flatMap { Library.rail.firstIndex(of: $0) } ?? 0
        var i = from + by
        while Library.rail.indices.contains(i) {
            if let at = firsts[Library.rail[i]] { jump(at); return }
            i += by
        }
    }
}

/** Where the slide is: the letter big in the middle of the screen. */
struct HeldLetter: View {
    let letter: Character

    var body: some View {
        Text(String(letter))
            .font(.system(size: 52, weight: .heavy))
            .foregroundStyle(Brand.orange)
            .frame(width: 96, height: 96)
            .background(Brand.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .allowsHitTesting(false)
    }
}

/** Where the header's bottom is on screen: the rail starts below it. */
struct HeaderEnd: PreferenceKey {
    static let defaultValue: CGFloat = -.infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
