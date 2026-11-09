import RadianceKit
import SwiftUI

/**
 * A Radiance Music Server's library (Android's ui/ServerLibrary.kt): its songs, some at a time and searched there for
 * a big library; a split song says so; each song's menu plays it next, queues it, saves it to this iPhone (a liked
 * song) or asks the server to split it; the songs being split there show above.
 */
struct ServerLibraryView: View {
    @Environment(AppModel.self) private var app
    let server: Server
    let header: AnyView
    @State private var songs: [ServerSong]?
    @State private var total = 0
    @State private var problem: String?
    @State private var filter = ""
    @State private var queue: SplitQueue?
    @State private var loadingMore = false

    static let pageSize = 60

    var body: some View {
        List {
            header.listRowBackground(Brand.night).listRowSeparator(.hidden)
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Brand.dim)
                    TextField("Search \(server.name)", text: $filter).autocorrectionDisabled().submitLabel(.search)
                    if !filter.isEmpty { Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.dim) } }
                }
                .padding(.horizontal, 14).frame(height: 44).background(Brand.card, in: Capsule())
                .listRowBackground(Brand.night).listRowSeparator(.hidden)
                if case .removed(let why) = app.servers.health[server.base] ?? .unknown {
                    Text(why).font(.system(size: 14)).foregroundStyle(Brand.heart).listRowBackground(Brand.night)
                }
                if let q = queue, let j = q.jobs.first(where: \.working) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Splitting on \(server.name)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Text("“\(j.title)”: \(j.note)").font(.system(size: 13)).foregroundStyle(Brand.dim).lineLimit(2)
                        ProgressView(value: j.progress).tint(Brand.orange)
                        let waiting = q.jobs.filter(\.waiting).count
                        if waiting > 0 { Text("\(waiting) more waiting").font(.system(size: 12)).foregroundStyle(Brand.dim) }
                    }
                    .padding(12).background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
                    .listRowBackground(Brand.night).listRowSeparator(.hidden)
                }
            }
            if let problem {
                ProblemView(text: problem, offline: !app.online) { Task { await load(reset: true) } }
                    .listRowBackground(Brand.night).listRowSeparator(.hidden)
            } else if let songs {
                if songs.isEmpty {
                    Note(filter.isEmpty ? "\(server.name) has no songs yet." : "Nothing on \(server.name) matches “\(filter)”.")
                        .listRowBackground(Brand.night)
                }
                let tracks = songs.map { $0.track() }
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    ServerSongRow(song: s, track: tracks[i], job: queue?.of(s.id)) { app.player.play(tracks, i) } menu: {
                        menu(s, tracks[i])
                    }
                    .listRowBackground(Brand.night)
                }
                if songs.count < total {
                    Button { Task { await load(reset: false) } } label: {
                        HStack { Text("More (\(total - songs.count) left)"); if loadingMore { Spacer(); ProgressView() } }
                    }
                    .listRowBackground(Brand.night)
                }
            } else {
                HStack { ProgressView(); Text("Getting \(server.name)'s songs…").foregroundStyle(Brand.dim) }
                    .listRowBackground(Brand.night)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load(reset: true) }
        .task(id: "\(server.first)|\(filter)") {
            if !filter.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            if Task.isCancelled { return }
            await load(reset: true)
        }
        .task(id: server.first) {
            while !Task.isCancelled {
                queue = try? await server.rms.queue()
                try? await Task.sleep(for: .seconds(queue?.jobs.contains(where: \.open) == true ? 3 : 20))
            }
        }
    }

    @ViewBuilder private func menu(_ s: ServerSong, _ t: Track) -> some View {
        Button { app.player.playNext(t) } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { app.player.enqueue(t) } label: { Label("Add to queue", systemImage: "text.badge.plus") }
        Button { if !app.isLiked(t) { app.toggleLike(t) } else { app.save(t) } } label: {
            Label(app.isLiked(t) ? "Saved to this iPhone" : "Save to this iPhone", systemImage: "arrow.down.circle")
        }
        if !s.split && server.can.split && queue?.of(s.id) == nil {
            Button { split(s) } label: { Label("Split on \(server.name)", systemImage: "scissors") }
        }
    }

    private func split(_ s: ServerSong) {
        Task {
            do {
                let a = try await server.rms.split(s.id)
                if a.alreadySplit { app.tell("“\(s.title)” is split there already.") }
                else { app.tell("“\(s.title)” is in \(server.name)'s split queue.") }
                queue = try? await server.rms.queue()
            } catch {
                app.tell((error as? Refused)?.words ?? Errors.say(error, online: app.online))
            }
        }
    }

    private func load(reset: Bool) async {
        if reset { problem = nil }
        loadingMore = !reset
        defer { loadingMore = false }
        do {
            let offset = reset ? 0 : (songs?.count ?? 0)
            let page = try await server.rms.page(filter.isEmpty ? nil : filter, offset: offset, limit: ServerLibraryView.pageSize)
            songs = reset ? page.songs : (songs ?? []) + page.songs
            total = page.total
            app.servers.healthy(server.base, .answering)
        } catch let r as Refused where r.removed {
            app.servers.healthy(server.base, .removed(why: r.words))
            problem = r.words
        } catch {
            problem = (error as? Refused)?.words ?? "Couldn't reach \(server.name). \(Errors.say(error, online: app.online))"
            if songs == nil { songs = nil }
        }
    }
}

/** A song on a server: tap plays from it; its split shows (done, or how far in the queue). */
struct ServerSongRow<Actions: View>: View {
    let song: ServerSong
    let track: Track
    let job: Job?
    let onPlay: () -> Void
    @ViewBuilder var menu: () -> Actions

    var body: some View {
        TrackRow(track: track, onPlay: onPlay) {
            if song.split {
                Text("Split").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.lossless)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Brand.lossless.opacity(0.14), in: Capsule())
            } else if let job {
                Text(job.working ? "\(Int(job.progress * 100)) %" : "Waiting").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.orange)
            }
            Menu { menu() } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.dim).frame(width: 36, height: 44)
            }
        }
    }
}
