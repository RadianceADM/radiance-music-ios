import RadianceKit
import SwiftUI

/*
 * Albums, Artists and Genres (Android's ui/ShelfScreens.kt, android#38), as the computer app has them: Library's pills
 * beside Liked Songs and History, each a grid of cards; a card opens its songs, with Play and Shuffle; Home has a row
 * of each. The grid's columns follow the width.
 */

/** How many songs, in words. */
func songCount(_ n: Int) -> String { "\(n) song\(n == 1 ? "" : "s")" }

/** The line under a card: an album's artist (when it's one), else how many songs. */
func under(_ kind: ShelfKind, _ g: RadianceKit.Group) -> String {
    if kind == .albums {
        let artists = Set(g.songs.map(\.artist))
        if artists.count == 1, let a = artists.first { return a }
    }
    return songCount(g.songs.count)
}

/** A genre's tile colour: one of Radiance's warm ones, the same for the same genre every time. */
func tone(_ name: String) -> Color {
    let tones: [UInt32] = [0x8A3B12, 0x5C2A12, 0x7A4A10, 0x3F2A55, 0x1F4D45, 0x6B1F2E, 0x2D3E66, 0x4B5320]
    // a steady hash (Swift's own changes every run)
    let h = name.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
    return Color(hex: tones[Int(h % UInt32(tones.count))])
}

/** An album (its cover), an artist (a song's cover in a circle: there are no artist photos) or a genre (a warm tile with a cover leaning in its corner). */
struct GroupCard: View {
    let kind: ShelfKind
    let group: RadianceKit.Group
    var size: CGFloat = 150

    var body: some View {
        let first = group.songs.first
        VStack(alignment: kind == .artists ? .center : .leading, spacing: 6) {
            switch kind {
            case .albums:
                if let first { CoverView(track: first, size: size, corner: 16) }
            case .artists:
                if let first { CoverView(track: first, size: size, corner: size / 2) }
            case .genres:
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [tone(group.name), tone(group.name).opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let first {
                        CoverView(track: first, size: size * 0.5, corner: 8)
                            .rotationEffect(.degrees(22))
                            .offset(x: size * 0.58, y: size * 0.56)
                    }
                    Text(group.name).font(.system(size: 19, weight: .heavy)).foregroundStyle(.white).lineLimit(3)
                        .padding(12).frame(width: size * 0.85, alignment: .leading)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if kind != .genres {
                Text(group.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Text(under(kind, group)).font(.system(size: 12)).foregroundStyle(Brand.dim).lineLimit(1)
        }
        .frame(width: size)
    }
}

/** A shelf's cards as a grid (Library). */
struct ShelfGrid: View {
    @Environment(AppModel.self) private var app
    let kind: ShelfKind

    var body: some View {
        let groups = Shelf.groups(app.library.liked, kind)
        if groups.isEmpty {
            Note("Like songs and your \(kind.title.lowercased()) show here.")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14, alignment: .top)], spacing: 18) {
                ForEach(groups) { g in
                    NavigationLink(value: ShelfPick(kind: kind, name: g.name)) { GroupCard(kind: kind, group: g) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/** Which album, artist or genre to open. */
struct ShelfPick: Hashable {
    let kind: ShelfKind
    let name: String
}

/** One album, artist or genre: its songs, with Play and Shuffle. */
struct GroupSongsView: View {
    @Environment(AppModel.self) private var app
    let pick: ShelfPick

    var body: some View {
        let g = Shelf.groups(app.library.liked, pick.kind).first { $0.name == pick.name }
        List {
            if let g {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 16) {
                        GroupCard(kind: pick.kind, group: g, size: 120)
                        Spacer(minLength: 0)
                    }
                    Text(g.name).font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                    Text(under(pick.kind, g) == songCount(g.songs.count) ? songCount(g.songs.count) : "\(under(pick.kind, g)) · \(songCount(g.songs.count))")
                        .font(.system(size: 14)).foregroundStyle(Brand.dim)
                    HStack(spacing: 10) {
                        Button { app.player.play(g.songs, 0) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                        Button { app.player.play(g.songs.shuffled(), 0) } label: { Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).tint(.white)
                    }
                    .controlSize(.large)
                }
                .listRowBackground(Brand.night).listRowSeparator(.hidden)
                ForEach(Array(g.songs.enumerated()), id: \.element.key) { i, t in
                    TrackRow(track: t, onPlay: { app.player.play(g.songs, i) }) { HeartButton(track: t) }
                        .listRowBackground(Brand.night)
                }
            } else {
                Note("Nothing here any more.").listRowBackground(Brand.night)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.night)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/** Home's row of albums, artists or genres. */
struct ShelfRow: View {
    @Environment(AppModel.self) private var app
    let kind: ShelfKind

    var body: some View {
        let groups = Shelf.groups(app.library.liked, kind).filter { $0.name != Shelf.finding }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Your \(kind.title.lowercased())")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(groups.prefix(20)) { g in
                            NavigationLink(value: ShelfPick(kind: kind, name: g.name)) { GroupCard(kind: kind, group: g) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 6)
        }
    }
}
