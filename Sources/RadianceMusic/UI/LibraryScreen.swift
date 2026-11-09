import RadianceKit
import SwiftUI

/**
 * Library (Android's LibraryScreen): Liked Songs (A to Z), History, Albums, Artists and Genres as pills, a search,
 * Play and Shuffle; each server you joined is one more pill (stage 5).
 */
struct LibraryScreen: View {
    @Environment(AppModel.self) private var app
    let onSettings: () -> Void

    enum Showing: Hashable { case liked, history, shelf(ShelfKind) }
    @State private var showing = Showing.liked
    @State private var filter = ""

    var body: some View {
        switch showing {
        case .shelf(let kind):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(songs: [])
                    ShelfGrid(kind: kind)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        case .liked, .history:
            songList
        }
    }

    private var songList: some View {
        let all = showing == .liked ? app.library.liked : app.library.history
        let songs = filter.isEmpty ? all : all.filter { matches($0, filter) }
        return List {
            header(songs: songs)
                .listRowBackground(Brand.night)
                .listRowSeparator(.hidden)
            if songs.isEmpty {
                Note(all.isEmpty ? (showing == .liked ? "Songs you like show here, A to Z, and play without the internet." : "Songs you play show here.") : "None of them match “\(filter)”.")
                    .listRowBackground(Brand.night).listRowSeparator(.hidden)
            }
            ForEach(Array(songs.enumerated()), id: \.offset) { i, t in
                TrackRow(track: t, onPlay: { app.player.play(songs, i) }) {
                    if t.file != nil { Image(systemName: "arrow.down.circle.fill").font(.system(size: 14)).foregroundStyle(Brand.dim).accessibilityLabel("Saved") }
                    HeartButton(track: t)
                }
                .listRowBackground(Brand.night)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func header(songs: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PageTitle(title: "Library", onSettings: onSettings)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    pill("Liked Songs", app.library.liked.count, .liked)
                    pill("History", app.library.history.count, .history)
                    ForEach(ShelfKind.allCases) { k in pill(k.title, nil, .shelf(k)) }
                }
            }
            .scrollIndicators(.hidden)
            if showing == .liked || showing == .history {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Brand.dim)
                    TextField(showing == .liked ? "Search your liked songs" : "Search what you played", text: $filter).autocorrectionDisabled()
                    if !filter.isEmpty { Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.dim) } }
                }
                .padding(.horizontal, 14).frame(height: 44).background(Brand.card, in: Capsule())
                if !songs.isEmpty {
                    HStack(spacing: 10) {
                        Button { app.player.play(songs, 0) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                        Button { app.player.play(songs.shuffled(), 0) } label: { Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).tint(.white)
                    }
                    .controlSize(.large)
                }
                if showing == .liked, let s = app.status {
                    Text(s).font(.system(size: 13)).foregroundStyle(Brand.dim)
                }
            }
        }
    }

    private func pill(_ label: String, _ count: Int?, _ which: Showing) -> some View {
        Button { showing = which; filter = "" } label: {
            Text(count.map { "\(label) \($0)" } ?? label).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(showing == which ? .black : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(showing == which ? Brand.orange : Brand.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
