import RadianceKit
import SwiftUI

enum Tab: Hashable { case home, search, library }

/** The app: Home, Search and Library as tabs, the song playing over them, Now Playing and Settings as sheets. */
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var phase
    @State private var tab = Tab.home
    @State private var nowPlaying = false
    @State private var settings = false
    /** How to use it, the first time the app opens (not while it's being checked from the laptop). */
    @State private var guide = Guide.due && !AppModel.checking

    var body: some View {
        @Bindable var party = app.party
        return ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                page { HomeScreen(onSearch: { tab = .search }, onSettings: { settings = true }) }
                    .tabItem { Label("Home", systemImage: "house.fill") }.tag(Tab.home)
                page { SearchScreen() }
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(Tab.search)
                page { LibraryScreen(onSettings: { settings = true }) }
                    .tabItem { Label("Library", systemImage: "music.note.list") }.tag(Tab.library)
            }
            if let n = app.notice {
                NoticeBar(notice: n)
                    .padding(.horizontal, 12)
                    .padding(.bottom, app.player.current == nil ? 60 : 130)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .modifier(SidebarOnWide())
        .animation(.spring(duration: 0.35), value: app.notice)
        .background(Brand.night)
        .sheet(isPresented: $nowPlaying) { NowPlayingScreen() }
        .sheet(isPresented: $settings) { SettingsScreen() }
        .sheet(isPresented: $party.shown) { PartyScreen() }
        .fullScreenCover(isPresented: $guide) { GuideScreen { Guide.seen(); guide = false } }
        .onChange(of: phase) { _, p in if p != .active { app.player.saveSession() } }
        // a link opened the app: Settings takes it (Now Playing steps aside first: one sheet at a time)
        .onOpenURL { app.opened($0) }
        .onChange(of: app.opening) { _, o in
            guard o != nil, !settings else { return }
            if nowPlaying {
                nowPlaying = false
                Task { try? await Task.sleep(for: .milliseconds(600)); settings = true }
            } else {
                settings = true
            }
        }
        .task {
            app.startUp()
            // checking from the laptop (AppModel.test)
            if app.test["RM_SEARCH"] != nil { tab = .search }
            if app.test["RM_OPEN"] == "library" { tab = .library }
            try? await Task.sleep(for: .seconds(Double(app.test["RM_OPEN_AFTER"] ?? "0") ?? 0))
            if let n = app.test["RM_PLAY_LIKED"].flatMap(Int.init), app.library.liked.indices.contains(n) { app.player.play(app.library.liked, n) }
            // the song playing split here (RM_SPLIT), and the Mixer's voice (RM_VOICE: song, karaoke, vocalsOnly)
            if app.test["RM_SPLIT"] != nil, let t = app.player.current { app.splitter.split(t) }
            if let v = app.test["RM_VOICE"].flatMap(Mixer.Voice.init(rawValue:)) { app.mixer.choose(v) }
            if app.test["RM_OPEN"] == "nowplaying" { nowPlaying = true }
            if app.test["RM_OPEN"] == "settings" { settings = true }
        }
    }

    /** A tab's page: on the night colour, the song playing above the tabs. */
    private func page<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        NavigationStack {
            content()
                .frame(maxWidth: Fit.page)
                .frame(maxWidth: .infinity)
                .background(Brand.night)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ShelfPick.self) { GroupSongsView(pick: $0) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if app.player.current != nil {
                // in a party, the song playing opens the party
                MiniPlayer(onOpen: { if app.party.joined { app.party.shown = true } else { nowPlaying = true } }).padding(.horizontal, 8).padding(.bottom, 6)
            }
        }
    }
}

/** The song playing, small: tap for Now Playing. */
struct MiniPlayer: View {
    @Environment(AppModel.self) private var app
    let onOpen: () -> Void

    var body: some View {
        let p = app.player
        if let t = p.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CoverView(track: t, size: 44, corner: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(p.problem ?? p.note ?? t.artist).font(.system(size: 13))
                            .foregroundStyle(p.problem != nil ? Brand.heart : Brand.dim).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    PlayButton(size: 22)
                    Button { p.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 20)).foregroundStyle(.white).frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Next")
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                ProgressView(value: p.duration > 0 ? min(p.position / p.duration, 1) : 0)
                    .tint(Brand.orange).scaleEffect(x: 1, y: 0.6).padding(.horizontal, 12).padding(.bottom, 4)
            }
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
    }
}

/** Play or pause; it spins while the song isn't here yet. */
struct PlayButton: View {
    @Environment(AppModel.self) private var app
    var size: CGFloat = 22
    var filled = false

    var body: some View {
        let p = app.player
        Button { p.toggle() } label: {
            ZStack {
                if filled { Circle().fill(.white).frame(width: size * 2.9, height: size * 2.9) }
                if p.buffering {
                    ProgressView().tint(filled ? .black : .white).controlSize(size > 26 ? .large : .regular)
                } else {
                    Image(systemName: p.playing ? "pause.fill" : "play.fill").font(.system(size: size)).foregroundStyle(filled ? .black : .white)
                }
            }
            .frame(width: max(44, filled ? size * 2.9 : 40), height: max(44, filled ? size * 2.9 : 44))
        }
        .accessibilityLabel(p.playing ? "Pause" : "Play")
    }
}

/** A notice at the bottom, with its one action. */
struct NoticeBar: View {
    @Environment(AppModel.self) private var app
    let notice: Notice

    var body: some View {
        HStack(spacing: 12) {
            Text(notice.words).font(.system(size: 14)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            if let label = notice.actionLabel, let action = notice.action {
                Button(label) { app.dismissNotice(); action() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { app.dismissNotice() }
    }
}

/**
 * Wide screens (Android's ui/Fit.kt): an iPad or a window 600 points across or more gets a sidebar in place of the
 * tabs (iOS 18 and up), and its pages stay a readable width.
 */
enum Fit {
    static let page: CGFloat = 840
}

struct SidebarOnWide: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}
