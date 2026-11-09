import RadianceKit
import SwiftUI

/** Home (Android's HomeScreen): the greeting and your mix, the songs played lately, your newest liked songs. */
struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    let onSearch: () -> Void
    let onSettings: () -> Void

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5...11: return "Good morning"
        case 12...17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        let liked = app.library.liked
        var seen = Set<String>()
        let recent = Array(app.library.history.filter { seen.insert($0.key).inserted }.prefix(20))
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(title: "Home", onSettings: onSettings)
                VStack(alignment: .leading, spacing: 8) {
                    Text(greeting).font(.system(size: 34, weight: .heavy)).tracking(-1).foregroundStyle(.white)
                    Text(liked.isEmpty ? "Search for a song, like it and it's saved on your iPhone." : "Your mix: \(liked.count) songs you liked, shuffled.")
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 10) {
                        if liked.isEmpty {
                            Button(action: onSearch) { Label("Search for music", systemImage: "magnifyingglass") }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button { app.player.play(liked.shuffled(), 0) } label: { Label("Play your mix", systemImage: "shuffle") }
                                .buttonStyle(.borderedProminent)
                            Button { app.player.play(liked, 0) } label: { Label("Liked, A to Z", systemImage: "textformat") }
                                .buttonStyle(.bordered).tint(.white)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sunset())
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                if !recent.isEmpty {
                    SectionTitle("Played lately").padding(.top, 6)
                    CardRow(songs: recent) { i in app.player.play(recent, i) }
                }
                if !liked.isEmpty {
                    let newest = Array(liked.suffix(20).reversed())
                    SectionTitle("Liked songs").padding(.top, 6)
                    CardRow(songs: newest) { i in app.player.play(newest, i) }
                    // as the computer app's Home: your albums, artists and genres (android#38); a card opens its songs
                    ForEach(ShelfKind.allCases) { ShelfRow(kind: $0) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

/** Songs as cards in a row you swipe along. */
struct CardRow: View {
    @Environment(AppModel.self) private var app
    let songs: [Track]
    let onPlay: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(Array(songs.enumerated()), id: \.element.key) { i, t in
                    VStack(alignment: .leading, spacing: 6) {
                        CoverView(track: t, size: 150, corner: 16)
                        Text(t.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(t.artist).font(.system(size: 12)).foregroundStyle(Brand.dim).lineLimit(1)
                    }
                    .frame(width: 150)
                    .contentShape(Rectangle())
                    .onTapGesture { onPlay(i) }
                    .contextMenu { SongMenu(track: t) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0)
    }
}
