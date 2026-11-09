import RadianceKit
import SwiftUI

/** Library (Android's LibraryScreen): Liked Songs (A to Z) and History as pills, a search, Play and Shuffle. */
struct LibraryScreen: View {
    @Environment(AppModel.self) private var app
    let onSettings: () -> Void
    @State private var showing = 0
    @State private var filter = ""

    var body: some View {
        let all = showing == 0 ? app.library.liked : app.library.history
        let songs = filter.isEmpty ? all : all.filter { matches($0, filter) }
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    PageTitle(title: "Library", onSettings: onSettings)
                    HStack(spacing: 8) {
                        pill("Liked Songs", app.library.liked.count, 0)
                        pill("History", app.library.history.count, 1)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Brand.dim)
                        TextField(showing == 0 ? "Search your liked songs" : "Search what you played", text: $filter).autocorrectionDisabled()
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
                }
                .listRowBackground(Brand.night)
                .listRowSeparator(.hidden)
            }
            if songs.isEmpty {
                Note(all.isEmpty ? (showing == 0 ? "Songs you like show here, A to Z, and play without the internet." : "Songs you play show here.") : "None of them match “\(filter)”.")
                    .listRowBackground(Brand.night).listRowSeparator(.hidden)
            }
            ForEach(Array(songs.enumerated()), id: \.element.key) { i, t in
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

    private func pill(_ label: String, _ count: Int, _ which: Int) -> some View {
        Button { showing = which } label: {
            Text("\(label) \(count)").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(showing == which ? .black : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(showing == which ? Brand.orange : Brand.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
