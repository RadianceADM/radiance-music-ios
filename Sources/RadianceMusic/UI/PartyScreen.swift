import RadianceKit
import SwiftUI

/**
 * The listening party you're in (Android's ui/PartyScreen.kt; owner's choice, 2026-10-31): the song everyone hears now
 * and how well this iPhone keeps time with it, reactions (soft pictures that float up), up next (anyone adds a song),
 * who's listening, and the host's controls. It plays on with the screen locked; Leave goes back to your own music.
 */
struct PartyScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var ending = false

    var body: some View {
        let party = app.party
        Group {
            if let n = party.now {
                ZStack {
                    List {
                        header(n).plainRow()
                        NowInParty(n: n).plainRow()
                        reactions.plainRow()
                        upNext(n)
                        listening(n).plainRow()
                        if n.host || n.server.me?.owner == true { hostCard(n).plainRow() }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: Fit.page)
                    Floats(floats: party.floats) { party.landed($0) }
                }
                .sheet(isPresented: $adding) { AddToParty(server: n.server) }
                .confirmationDialog("End the party?", isPresented: $ending, titleVisibility: .visible) {
                    Button("End it", role: .destructive) { party.end() }
                    Button("Keep it on", role: .cancel) {}
                } message: {
                    Text("It stops for everyone listening (\(n.state.members.count)). The songs stay on \(n.server.name).")
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.night)
        // left, or it ended: back to where you were
        .onChange(of: party.joined) { _, on in if !on { dismiss() } }
    }

    private func header(_ n: Party.Now) -> some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44) }
                .tint(.white).accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 1) {
                Text("Listening party").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
                Text(n.server.name).font(.system(size: 14)).foregroundStyle(Brand.dim).lineLimit(1)
            }
            Spacer()
            Button { app.party.leave() } label: { Label("Leave", systemImage: "rectangle.portrait.and.arrow.right").labelStyle(.titleAndIcon) }
                .tint(Brand.orange)
        }
        .padding(.top, 4)
    }

    /** The six reactions, as round buttons with their soft pictures. */
    private var reactions: some View {
        HStack {
            ForEach(Reactions.all, id: \.emoji) { r in
                Button { app.party.react(r.emoji) } label: {
                    ReactionIcon(emoji: r.emoji, size: 30).frame(width: 50, height: 50).background(Brand.card, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(r.name)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private func upNext(_ n: Party.Now) -> some View {
        HStack {
            Text("Up next").font(.system(size: 21, weight: .heavy)).foregroundStyle(.white)
            Spacer()
            Button { adding = true } label: { Label("Add a song", systemImage: "text.badge.plus").labelStyle(.titleAndIcon) }
                .buttonStyle(.bordered).tint(.white)
        }
        .padding(.top, 14)
        .plainRow()
        if n.state.queue.isEmpty {
            Note("Nothing waiting. Anyone in the party can add a song from \(n.server.name).").plainRow()
        }
        ForEach(Array(n.state.queue.enumerated()), id: \.element.entry) { i, e in
            let mine = e.addedBy?.id == n.me?.id
            HStack(spacing: 12) {
                CoverView(track: e.track(), size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text([e.artist.isEmpty ? nil : e.artist, e.addedBy.map { "added by \(mine ? "you" : $0.name)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Brand.dim).lineLimit(1)
                }
                Spacer(minLength: 4)
                if n.controls || mine {
                    Menu {
                        if n.controls && i > 0 {
                            Button { app.party.reorder(e.entry, to: 0) } label: { Label("Play it next", systemImage: "arrow.up.to.line") }
                            Button { app.party.reorder(e.entry, to: i - 1) } label: { Label("Move up", systemImage: "arrow.up") }
                        }
                        if n.controls && i < n.state.queue.count - 1 {
                            Button { app.party.reorder(e.entry, to: i + 1) } label: { Label("Move down", systemImage: "arrow.down") }
                        }
                        Button(role: .destructive) { app.party.remove(e.entry) } label: { Label("Take it out of the party", systemImage: "minus.circle") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.dim).frame(width: 36, height: 44)
                    }
                    .accessibilityLabel("More for “\(e.title)”")
                }
            }
            .plainRow()
        }
    }

    private func listening(_ n: Party.Now) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Listening").font(.system(size: 21, weight: .heavy)).foregroundStyle(.white)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if n.state.members.isEmpty { Text("Nobody is listening right now.").foregroundStyle(Brand.dim) }
                    ForEach(n.state.members, id: \.id) { m in
                        HStack(spacing: 8) {
                            Text(String(m.name.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundStyle(Brand.glow)
                                .frame(width: 28, height: 28).background(Brand.orange.opacity(0.22), in: Circle())
                            Text(m.id == n.me?.id ? "\(m.name) (you)" : m.name).foregroundStyle(.white)
                            if m.host {
                                Text("Host").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.night)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(Brand.orange, in: Capsule())
                            }
                        }
                        .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
                        .background(Brand.card, in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 18)
    }

    /** For the host (and the server's owner): who controls the party, and ending it. */
    private func hostCard(_ n: Party.Now) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(n.host ? "You're the host" : "Your server").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.dim)
            if n.host {
                Text(n.state.everyoneControls ? "Everyone can play, pause and skip." : "Only you play, pause and skip. Everyone can add songs and react.")
                    .font(.system(size: 14)).foregroundStyle(Brand.dim)
                Button { app.party.allow(everyone: !n.state.everyoneControls) } label: {
                    n.state.everyoneControls
                        ? Label("Only I control it", systemImage: "person.fill").labelStyle(.titleAndIcon)
                        : Label("Let everyone control it", systemImage: "person.3.fill").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered).tint(.white)
            }
            Button { ending = true } label: { Label("End the party for everyone", systemImage: "stop.circle").labelStyle(.titleAndIcon) }
                .tint(Brand.orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.top, 20).padding(.bottom, 28)
    }
}

/** The song everyone hears: its cover, who added it, how far along, and this iPhone keeping time with it. */
private struct NowInParty: View {
    @Environment(AppModel.self) private var app
    let n: Party.Now

    var body: some View {
        let p = n.state
        let s = p.song
        VStack(spacing: 0) {
            if let s {
                CoverView(track: s.track(), size: 240).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(.top, 10)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Brand.card).frame(width: 240, height: 240)
                    .overlay(Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(.white.opacity(0.3))).padding(.top, 10)
            }
            HStack(spacing: 8) {
                let on = p.playing && s != nil
                Text(s == nil ? "Quiet" : p.playing ? "Playing" : "Paused").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(on ? Brand.night : .white).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(on ? Brand.orange : Brand.card, in: Capsule())
                Text(n.host ? "You're the host" : "Hosted by \(p.host?.name ?? "someone")").font(.system(size: 14)).foregroundStyle(Brand.dim)
            }
            .padding(.top, 18)
            Text(s?.title ?? "Nothing playing").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                .multilineTextAlignment(.center).padding(.top, 10)
            Text(s == nil ? "Add a song: it starts at once." : [s!.artist.isEmpty ? nil : s!.artist, s!.addedBy.map { "added by \($0.id == n.me?.id ? "you" : $0.name)" }].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 14)).foregroundStyle(Brand.dim).lineLimit(1)
            if let s {
                // how far along, by the party's clock (four times a second)
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let at = max(app.party.position() ?? 0, 0)
                    let length = s.durationMs ?? 0
                    VStack(spacing: 4) {
                        ProgressView(value: length > 0 ? min(Double(at) / Double(length), 1) : 0).tint(.white)
                        HStack {
                            Text(clock(Int(at / 1000)))
                            Spacer()
                            if length > 0 { Text(clock(Int(length / 1000))) }
                        }
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Brand.dim)
                    }
                }
                .padding(.top, 14)
            }
            // what this iPhone is doing: in step (and by how much), catching up, paused by the host…
            HStack(spacing: 8) {
                if !n.linked { ProgressView().controlSize(.small).tint(Brand.orange) }
                Text(n.sync + (n.clockMs.map { " · clock ±\($0) ms" } ?? "")).font(.system(size: 12))
                    .foregroundStyle(n.linked ? Brand.dim : Brand.glow).multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            HStack(spacing: 10) {
                if n.controls {
                    if p.playing && s != nil {
                        Button { app.party.pause() } label: { Label("Pause", systemImage: "pause.fill").labelStyle(.titleAndIcon) }.buttonStyle(.borderedProminent)
                    } else {
                        Button { app.party.play() } label: { Label("Play", systemImage: "play.fill").labelStyle(.titleAndIcon) }.buttonStyle(.borderedProminent)
                            .disabled(s == nil && p.queue.isEmpty)
                    }
                    Button { app.party.skip() } label: { Label("Skip", systemImage: "forward.fill").labelStyle(.titleAndIcon) }.buttonStyle(.bordered).tint(.white)
                        .disabled(s == nil)
                } else {
                    Text("\(p.host?.name ?? "The host") (the host) plays, pauses and skips.").font(.system(size: 14)).foregroundStyle(Brand.dim)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 14)
            // this iPhone only: the party goes on either way
            if n.listening {
                Button { app.party.listenHere(false) } label: { Label("Stop listening here", systemImage: "speaker.slash").labelStyle(.titleAndIcon) }
                    .tint(Brand.dim).padding(.top, 8)
            } else {
                Button { app.party.listenHere(true) } label: { Label("Listen here", systemImage: "headphones").labelStyle(.titleAndIcon) }
                    .buttonStyle(.bordered).tint(.white).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

/** Reactions as they come float up the screen and fade. */
private struct Floats: View {
    let floats: [Party.Floating]
    let landed: (Int) -> Void

    var body: some View {
        GeometryReader { g in
            ForEach(floats) { f in
                Rising(f: f, size: g.size) { landed(f.id) }
            }
        }
        .allowsHitTesting(false)
    }

    private struct Rising: View {
        let f: Party.Floating
        let size: CGSize
        let done: () -> Void
        @State private var up = false
        @State private var x = CGFloat.random(in: 0.15...0.85)
        @Environment(\.accessibilityReduceMotion) private var still

        var body: some View {
            VStack(spacing: 2) {
                ReactionIcon(emoji: f.reaction.emoji, size: 48)
                if let by = f.reaction.by { Text(by.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8)) }
            }
            .scaleEffect(up ? 1.2 : 0.8)
            .opacity(up ? 0 : 1)
            .position(x: size.width * x, y: size.height * (still ? 0.6 : up ? 0.25 : 0.85))
            .onAppear {
                withAnimation(.linear(duration: 2.7)) { up = true }
                Task { try? await Task.sleep(for: .seconds(2.8)); done() }
            }
        }
    }
}

/** Anyone adds a song from the server's library: it joins the queue (it starts at once when nothing's playing). */
private struct AddToParty: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let server: Server
    @State private var songs: [ServerSong]?
    @State private var total = 0
    @State private var problem: String?
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            List {
                Text("From \(server.name). It plays after the songs before it.").font(.system(size: 14)).foregroundStyle(Brand.dim).plainRow()
                if let problem {
                    ProblemView(text: problem, offline: !app.online) { Task { await load() } }.plainRow()
                } else if let songs {
                    if songs.isEmpty {
                        Note(filter.isEmpty ? "\(server.name) has no songs yet." : "Nothing on \(server.name) matches “\(filter)”.").plainRow()
                    }
                    ForEach(songs, id: \.id) { song in
                        Button { app.party.add(song.id); dismiss() } label: {
                            HStack(spacing: 12) {
                                CoverView(track: song.track(), size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                    Text(song.artist).font(.system(size: 13)).foregroundStyle(Brand.dim).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "text.badge.plus").foregroundStyle(Brand.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add “\(song.title)”")
                        .plainRow()
                    }
                    if songs.count < total {
                        Text("Search for the other \(total - songs.count).").font(.system(size: 13)).foregroundStyle(Brand.dim).plainRow()
                    }
                } else {
                    HStack { ProgressView(); Text("Getting \(server.name)'s songs…").foregroundStyle(Brand.dim) }.plainRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Brand.sheet)
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(server.name)")
            .navigationTitle("Add a song to the party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            // its songs (a big library: some at a time, a search finds the rest there)
            .task(id: filter) {
                if !filter.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                if !Task.isCancelled { await load() }
            }
        }
    }

    private func load() async {
        problem = nil
        do {
            let page = try await server.rms.page(filter.isEmpty ? nil : filter, limit: 200)
            songs = page.songs
            total = page.total
        } catch {
            problem = (error as? Refused)?.words ?? "Couldn't reach \(server.name). \(Errors.say(error, online: app.online))"
        }
    }
}

/**
 * A server's listening party, at the top of its library (Android's PartyCard): join the one that's on, start one
 * (when its owner lets you host), or open the one you're in.
 */
struct PartyCard: View {
    @Environment(AppModel.self) private var app
    let server: Server
    let state: PartyState?
    @State private var choosing = false

    var body: some View {
        let here = app.party.now?.server.base == server.base
        let on = state?.on == true
        if here || on || server.can.host {
            HStack(spacing: 12) {
                Image(systemName: "person.wave.2.fill").font(.system(size: 22)).foregroundStyle(Brand.orange)
                    .frame(width: 44, height: 44).background(Brand.orange.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(here ? "You're in the party" : on ? "A listening party is on" : "Listening party").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Text(words(here: here, on: on)).font(.system(size: 13)).foregroundStyle(Brand.dim).lineLimit(2)
                }
                Spacer(minLength: 4)
                if here {
                    Button { app.party.shown = true } label: { Label("Open", systemImage: "chevron.up").labelStyle(.titleAndIcon) }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                } else if on {
                    Button { app.party.join(server); app.party.shown = true } label: { Label("Join", systemImage: "arrow.right.circle.fill").labelStyle(.titleAndIcon) }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                } else {
                    Button { choosing = true } label: { Label("Start", systemImage: "balloon.fill").labelStyle(.titleAndIcon) }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                }
            }
            .padding(12)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .confirmationDialog("Who plays, pauses and skips?", isPresented: $choosing, titleVisibility: .visible) {
                Button("Only me") { app.party.start(server, everyone: false) { app.party.shown = true } }
                Button("Everyone") { app.party.start(server, everyone: true) { app.party.shown = true } }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Everyone in the party hears the same song at the same moment. You're the host; you can let everyone control it later.")
            }
        }
    }

    private func words(here: Bool, on: Bool) -> String {
        if here { return app.party.now?.sync ?? "" }
        if on, let s = state {
            let who = s.host?.name ?? "someone"
            return "Hosted by \(who) · \(s.members.count) listening" + (s.song.map { " · “\($0.title)”" } ?? "")
        }
        return "Everyone hears the same song at the same moment, on \(server.name)."
    }
}

extension View {
    /** A row of the party's lists: on the night colour, no line under it. */
    fileprivate func plainRow() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
    }
}
