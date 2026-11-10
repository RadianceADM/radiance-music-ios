import RadianceKit
import SwiftUI

/**
 * How to use it, the first time the app opens (Android's ui/Guide.kt; owner, 2026-10-31: "add a easy how to use, upon
 * first enter on app"): five cards to swipe through, a few plain words each. Skip any time; Settings → How to use it
 * shows them again.
 */
enum Guide {
    private static let key = "guide.seen"

    /** Not seen yet: the first time the app opens. */
    static var due: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func seen() { UserDefaults.standard.set(true, forKey: key) }

    struct Card: Hashable {
        let icon: String
        let title: String
        let words: String
    }

    static let cards = [
        Card(icon: "magnifyingglass", title: "Search any song",
             words: "Type a song or an artist. Lossless plays first when there is one; YouTube Music has the rest."),
        Card(icon: "heart.fill", title: "Like it, it's yours",
             words: "Tap the heart. The song, its cover and its lyrics are saved on your iPhone and play with no internet."),
        Card(icon: "music.mic", title: "Karaoke in one tap",
             words: "In Now Playing, tap the mic: the singing goes, and the song is split right on your iPhone first if it isn't yet. Hold the mic for the Mixer, to keep a little of the singing."),
        Card(icon: "square.and.arrow.up", title: "Put it on your story",
             words: "Tap Share in Now Playing: the cover, or up to 150 characters of lyrics, for Instagram, Facebook or Messenger."),
        Card(icon: "hand.draw", title: "Swipe and send",
             words: "Swipe the cover for the next or the last song. Send songs to another phone or the computer by QR, in Settings."),
    ]
}

struct GuideScreen: View {
    let onDone: () -> Void
    @State private var page = 0

    var body: some View {
        let last = page == Guide.cards.count - 1
        ZStack {
            Brand.night.ignoresSafeArea()
            // the sunset's glow, as the start screen's
            RadialGradient(colors: [Brand.orange.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 700).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("How to use it").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.dim)
                    Spacer()
                    if !last { Button { onDone() } label: { Label("Skip", systemImage: "forward.end").labelStyle(.titleAndIcon) }.tint(.white) }
                }
                .padding(.horizontal, 20).frame(height: 44)
                TabView(selection: $page) {
                    ForEach(Array(Guide.cards.enumerated()), id: \.offset) { i, card in
                        CardView(card: card).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // where you are: a dot each, the current one long
                HStack(spacing: 8) {
                    ForEach(Guide.cards.indices, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == page ? 1 : 0.3)).frame(width: i == page ? 24 : 8, height: 8)
                    }
                }
                .animation(.spring(duration: 0.3), value: page)
                .padding(.vertical, 18)
                .accessibilityHidden(true)
                Button {
                    if last { onDone() } else { withAnimation { page += 1 } }
                } label: {
                    Label(last ? "Start listening" : "Next", systemImage: last ? "play.fill" : "arrow.right")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Brand.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 460)
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    private struct CardView: View {
        let card: Guide.Card
        @Environment(\.verticalSizeClass) private var height

        var body: some View {
            Group {
                if height == .compact {
                    // a phone on its side: the picture beside the words
                    HStack(spacing: 36) { picture; words(.leading) }.frame(maxWidth: Fit.page)
                } else {
                    VStack(spacing: 40) { picture; words(.center) }.frame(maxWidth: 460)
                }
            }
            .padding(.horizontal, 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        /** Its icon on a dark disc, in the sunset's glow. */
        private var picture: some View {
            ZStack {
                Circle().fill(RadialGradient(colors: [Brand.glow.opacity(0.55), Brand.orange.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 84))
                    .frame(width: 168, height: 168)
                Circle().fill(Brand.card).frame(width: 104, height: 104)
                Image(systemName: card.icon).font(.system(size: 44, weight: .semibold)).foregroundStyle(Brand.orange)
            }
            .accessibilityHidden(true)
        }

        private func words(_ align: HorizontalAlignment) -> some View {
            VStack(alignment: align, spacing: 14) {
                Text(card.title).font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                Text(card.words).font(.system(size: 17)).foregroundStyle(.white.opacity(0.75)).lineSpacing(5)
            }
            .multilineTextAlignment(align == .center ? .center : .leading)
        }
    }
}
