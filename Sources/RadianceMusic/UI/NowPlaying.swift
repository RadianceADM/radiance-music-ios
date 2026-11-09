import RadianceKit
import SwiftUI

/**
 * Now Playing (Android's NowPlaying): the cover's own colours flowing behind, the cover (swipe it for the next or the
 * one before) or the lyrics, the song, where in it, the controls, and what's next. Wider than tall: the cover or
 * lyrics on the left, the controls on the right.
 */
struct NowPlayingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing: Double?
    @State private var showQueue = false
    @State private var showMixer = false
    @State private var sharing: (Track, String?)?
    @AppStorage("nowplaying.lyrics") private var showLyrics = false

    var body: some View {
        let p = app.player
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Backdrop(track: p.current)
                if let t = p.current {
                    if wide {
                        HStack(spacing: 28) {
                            Group {
                                if showLyrics { LyricsView(track: t, onShareLine: { sharing = (t, $0) }).frame(maxWidth: geo.size.width * 0.5) }
                                else { cover(t, size: min(geo.size.height - 60, geo.size.width * 0.42)) }
                            }
                            .frame(maxHeight: .infinity)
                            VStack { handle; Spacer(); controls(t) }.frame(maxWidth: 460)
                        }
                        .padding(20)
                    } else {
                        VStack(spacing: 18) {
                            handle
                            if showLyrics {
                                HStack(spacing: 12) {
                                    CoverView(track: t, size: 52, corner: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                                        Text(t.artist).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                LyricsView(track: t, onShareLine: { sharing = (t, $0) }).frame(maxHeight: .infinity)
                                transport(t)
                            } else {
                                Spacer(minLength: 0)
                                cover(t, size: min(geo.size.width - 48, geo.size.height * 0.45))
                                Spacer(minLength: 0)
                                controls(t)
                            }
                        }
                        .padding(.horizontal, 24).padding(.bottom, 12)
                    }
                } else {
                    Note("Nothing playing.")
                }
            }
        }
        .sheet(isPresented: $showQueue) { QueueScreen() }
        .sheet(isPresented: $showMixer) { if let t = app.player.current { MixerSheet(track: t) } }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let (t, line) = sharing { ShareSongSheet(track: t, lyrics: line) }
        }
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
                    Text(t.byline()).font(.system(size: 16)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
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
                Text(note).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading)
            }
            transport(t)
        }
    }

    /** Where in the song, the buttons, and the row under them (lyrics, more, up next). */
    private func transport(_ t: Track) -> some View {
        let p = app.player
        return VStack(spacing: 18) {
            VStack(spacing: 4) {
                let total = max(p.duration, 1)
                Slider(value: Binding(get: { scrubbing ?? min(p.position, total) }, set: { scrubbing = $0 }), in: 0...total) { editing in
                    if !editing, let s = scrubbing { p.seek(s); scrubbing = nil }
                }
                .tint(.white)
                HStack {
                    Text(clock(Int(scrubbing ?? p.position))).font(.system(size: 12).monospacedDigit())
                    Spacer()
                    Text(p.duration > 0 ? "-" + clock(Int(max(0, p.duration - (scrubbing ?? p.position)))) : "–:––").font(.system(size: 12).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            HStack {
                Button { p.toggleShuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 20)).foregroundStyle(p.shuffle ? Brand.orange : .white.opacity(0.7)).frame(width: 44, height: 44)
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
                        .foregroundStyle(p.repeatMode == .off ? .white.opacity(0.7) : Brand.orange).frame(width: 44, height: 44)
                }
                .accessibilityLabel(p.repeatMode == .off ? "Repeat off" : p.repeatMode == .all ? "Repeat all" : "Repeat this song")
            }
            HStack {
                // lyrics: a speech bubble with quote marks in it (as Apple Music's), lit while on
                Button { withAnimation(.easeInOut(duration: 0.3)) { showLyrics.toggle() } } label: {
                    Image(systemName: "quote.bubble").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(showLyrics ? .black : .white)
                        .frame(width: 40, height: 40)
                        .background(showLyrics ? Color.white : Color.clear, in: Circle())
                }
                .accessibilityLabel(showLyrics ? "Hide lyrics" : "Lyrics")
                Spacer()
                // karaoke: tap for it (or back to the song), hold for the Mixer
                let m = app.mixer
                let on = m.voice != .song
                Image(systemName: "music.mic").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? .black : (m.available ? .white : .white.opacity(0.35)))
                    .frame(width: 40, height: 40)
                    .background(on ? Color.white : Color.clear, in: Circle())
                    .onTapGesture { if m.available { m.choose(on ? .song : .karaoke) } else { showMixer = true } }
                    .onLongPressGesture { showMixer = true }
                    .accessibilityLabel(on ? "Karaoke on" : "Karaoke")
                    .accessibilityAddTraits(.isButton)
                Spacer()
                Menu {
                    SongMenu(track: t)
                    Button { showMixer = true } label: { Label("Mixer", systemImage: "slider.vertical.3") }
                    Button { sharing = (t, nil) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40)
                }
                .accessibilityLabel("More")
                Spacer()
                // share it: a story card with its cover or the lyrics you pick
                Button { sharing = (t, nil) } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Share")
                Spacer()
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Up next")
            }
        }
    }
}

/**
 * The art's own colours, blurred, flowing like a lava lamp (Android's Backdrop): the whole cover slowly turning, with
 * soft patches of it wandering over it; darkened so white words read on any cover.
 */
struct Backdrop: View {
    @Environment(AppModel.self) private var app
    let track: Track?
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                Brand.sheet
                if let image {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let turn = (t / 120).truncatingRemainder(dividingBy: 1) * 360
                        let drift = sin(t * 2 * .pi / 22)
                        let sway = sin(t * 2 * .pi / 26)
                        ZStack {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: side * 1.15, height: side * 1.15)
                                .rotationEffect(.degrees(turn))
                                .blur(radius: 60)
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: side * 0.7, height: side * 0.7).clipShape(Circle())
                                .rotationEffect(.degrees(-turn * 1.6)).opacity(0.75).blur(radius: 50)
                                .offset(x: geo.size.width * (-0.2 + 0.12 * drift), y: geo.size.height * (-0.2 + 0.1 * sway))
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: side * 0.6, height: side * 0.6).clipShape(Circle())
                                .rotationEffect(.degrees(turn * 1.3 + 90)).opacity(0.7).blur(radius: 50)
                                .offset(x: geo.size.width * (0.15 - 0.1 * sway), y: geo.size.height * (0.25 + 0.08 * drift))
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .transition(.opacity)
                }
                LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .task(id: track?.key) {
            guard let track else { image = nil; return }
            let img = await app.covers.image(track, px: Art.medium)
            withAnimation(.easeInOut(duration: 0.8)) { image = img }
        }
    }
}

/**
 * The lyrics (Android's LyricsView): the line being sung drawn big and kept in view; tap a line to go there. None
 * found while offline says so, with Try again, and looks again when the iPhone's back online.
 */
struct LyricsView: View {
    @Environment(AppModel.self) private var app
    let track: Track
    /** Hold a line: share it on a story. */
    var onShareLine: (String) -> Void = { _ in }
    @State private var lyrics: Lyrics?
    @State private var offline = false
    @State private var tries = 0

    var body: some View {
        Group {
            switch lyrics {
            case nil:
                Text("Looking for lyrics…").foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .none?:
                if offline {
                    ProblemView(text: "You're offline. Connect to see the lyrics.", offline: true) { tries += 1 }
                } else {
                    Text("No lyrics found for this song.").foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .plain(let text)?:
                ScrollView {
                    Text(text).font(.system(size: 20, weight: .semibold)).lineSpacing(8).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
            case .timed(let lines)?:
                TimedLyrics(lines: lines, onShareLine: onShareLine)
            }
        }
        .task(id: "\(track.key)|\(tries)") {
            lyrics = nil
            let found = await Saver.lyrics(app.paths, track)
            offline = found == .none && !app.online
            lyrics = found
        }
        .onChange(of: app.online) { _, up in if up && offline { tries += 1 } }
    }
}

/** Timed lines: the one being sung lit, big and kept in view; tap one to go there. */
struct TimedLyrics: View {
    @Environment(AppModel.self) private var app
    let lines: [Line]
    var onShareLine: (String) -> Void = { _ in }

    var body: some View {
        // a line shows just before it's sung
        let at = app.player.position + 0.3
        let now = max(0, (lines.lastIndex { $0.start <= at }) ?? 0)
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Color.clear.frame(height: 30)
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        let sung = i == now
                        Text(line.text)
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(.white.opacity(sung ? 1 : (i < now ? 0.28 : 0.38)))
                            .scaleEffect(sung ? 1 : 0.94, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { app.player.seek(line.start) }
                            .onLongPressGesture { onShareLine(line.text) }
                            .animation(.easeOut(duration: 0.4), value: sung)
                            .id(i)
                    }
                    Color.clear.frame(height: 240)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: now) { _, n in withAnimation(.easeInOut(duration: 0.5)) { reader.scrollTo(max(0, n - 1), anchor: .top) } }
            .onAppear { reader.scrollTo(max(0, now - 1), anchor: .top) }
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
                    .listRowBackground(Brand.sheet)
                }
                .onMove { p.move(from: $0, to: $1) }
                .onDelete { p.remove(at: $0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Brand.sheet)
            .navigationTitle("Up next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button { p.toggleShuffle() } label: { Image(systemName: "shuffle").foregroundStyle(p.shuffle ? Brand.orange : .white) }
                        Button { p.cycleRepeat() } label: { Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(p.repeatMode == .off ? .white : Brand.orange) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { HStack { EditButton(); Button("Done") { dismiss() } } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
