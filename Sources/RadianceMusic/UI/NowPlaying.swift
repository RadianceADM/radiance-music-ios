import RadianceKit
import SwiftUI

/** Now Playing (Android's NowPlaying, stage 1): the cover, the song, where in it, the controls, and what's next. */
struct NowPlayingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing: Double?
    @State private var showQueue = false

    var body: some View {
        let p = app.player
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Brand.night.ignoresSafeArea()
                if let t = p.current {
                    if wide {
                        HStack(spacing: 28) {
                            cover(t, size: min(geo.size.height - 40, geo.size.width * 0.42))
                            controls(t).frame(maxWidth: 460)
                        }
                        .padding(20)
                    } else {
                        VStack(spacing: 22) {
                            handle
                            Spacer(minLength: 0)
                            cover(t, size: min(geo.size.width - 48, geo.size.height * 0.45))
                            Spacer(minLength: 0)
                            controls(t)
                        }
                        .padding(.horizontal, 24).padding(.bottom, 12)
                    }
                } else {
                    Note("Nothing playing.")
                }
            }
        }
        .sheet(isPresented: $showQueue) { QueueScreen() }
        .presentationDragIndicator(.hidden)
    }

    private var handle: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Close")
    }

    private func cover(_ t: Track, size: CGFloat) -> some View {
        CoverView(track: t, size: max(size, 120), corner: 24)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .gesture(DragGesture(minimumDistance: 30).onEnded { g in
                // swipe the cover: the next song, or the one before
                if g.translation.width < -60 { app.player.next() } else if g.translation.width > 60 { app.player.previousSong() }
            })
    }

    private func controls(_ t: Track) -> some View {
        let p = app.player
        return VStack(spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    Text(t.byline()).font(.system(size: 16)).foregroundStyle(Brand.dim).lineLimit(1)
                }
                Spacer()
                QualityBadge(track: t)
                HeartButton(track: t, size: 24)
            }
            if let why = p.problem {
                HStack {
                    Text(why).font(.system(size: 14)).foregroundStyle(Brand.heart)
                    Spacer()
                    Button("Retry") { p.retry() }.font(.system(size: 14, weight: .semibold))
                }
            } else if let note = p.note {
                Text(note).font(.system(size: 14)).foregroundStyle(Brand.dim).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 4) {
                let total = max(p.duration, 1)
                Slider(value: Binding(get: { scrubbing ?? min(p.position, total) }, set: { scrubbing = $0 }), in: 0...total) { editing in
                    if !editing, let s = scrubbing { p.seek(s); scrubbing = nil }
                }
                .tint(.white)
                HStack {
                    Text(clock(Int(scrubbing ?? p.position))).font(.system(size: 12).monospacedDigit())
                    Spacer()
                    Text(p.duration > 0 ? clock(Int(p.duration)) : "–:––").font(.system(size: 12).monospacedDigit())
                }
                .foregroundStyle(Brand.dim)
            }
            HStack {
                Button { p.toggleShuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 20)).foregroundStyle(p.shuffle ? Brand.orange : Brand.dim).frame(width: 44, height: 44)
                }
                .accessibilityLabel(p.shuffle ? "Shuffle on" : "Shuffle off")
                Spacer()
                Button { p.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 28)).foregroundStyle(.white).frame(width: 56, height: 56) }
                    .accessibilityLabel("Previous")
                Spacer()
                PlayButton(size: 26, filled: true)
                Spacer()
                Button { p.next() } label: { Image(systemName: "forward.fill").font(.system(size: 28)).foregroundStyle(.white).frame(width: 56, height: 56) }
                    .accessibilityLabel("Next")
                Spacer()
                Button { p.cycleRepeat() } label: {
                    Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 20))
                        .foregroundStyle(p.repeatMode == .off ? Brand.dim : Brand.orange).frame(width: 44, height: 44)
                }
                .accessibilityLabel(p.repeatMode == .off ? "Repeat off" : p.repeatMode == .all ? "Repeat all" : "Repeat this song")
            }
            HStack {
                Menu {
                    SongMenu(track: t)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(Brand.dim).frame(width: 44, height: 44)
                }
                Spacer()
                Button { showQueue = true } label: {
                    Label("Up next", systemImage: "list.bullet").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
    }
}

/** What plays next: tap one to play it, drag to move, swipe to take it out. */
struct QueueScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = app.player
        NavigationStack {
            List {
                ForEach(Array(p.queue.enumerated()), id: \.offset) { i, t in
                    TrackRow(track: t, onPlay: { p.playAt(i) }) {
                        if i == p.index { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Brand.orange) }
                    }
                    .listRowBackground(Brand.night)
                }
                .onMove { p.move(from: $0, to: $1) }
                .onDelete { p.remove(at: $0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Brand.night)
            .navigationTitle("Up next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
