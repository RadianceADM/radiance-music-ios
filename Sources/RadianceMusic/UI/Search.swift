import RadianceKit
import SwiftUI

/**
 * Search (Android's SearchScreen): suggestions as you type, then lossless FLAC from the Internet Archive first and
 * YouTube Music after, your liked matches above them. A song from search plays with songs like it after it.
 */
struct SearchScreen: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var asked = ""
    @State private var suggestions: [String] = []
    @State private var results: [Track]?
    @State private var busy = false
    @State private var problem: String?
    @State private var offline = false
    @State private var tries = 0
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.dim)
                TextField("Search any song or artist", text: $query)
                    .focused($typing)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { search(query) }
                if !query.isEmpty {
                    Button { clear() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.dim) }
                        .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(Brand.card, in: Capsule())
            .padding(16)

            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { query = s; search(s) } label: {
                                Text(s).font(.system(size: 14)).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 8).background(Brand.card, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 8)
            }
            content
            Spacer(minLength: 0)
        }
        .task(id: query) { await suggest() }
        .task(id: "\(asked)|\(tries)") { await look() }
        .onChange(of: app.online) { _, up in if up && offline && !asked.isEmpty { tries += 1 } }
        .onAppear {
            // checking from the laptop (AppModel.test)
            if let q = app.test["RM_SEARCH"], query.isEmpty { query = q; search(q) }
        }
    }

    @ViewBuilder private var content: some View {
        let liked = app.library.liked
        if busy {
            ProgressView().tint(Brand.orange).controlSize(.large).padding(40)
        } else if let list = results {
            if list.isEmpty, let problem {
                ScrollView {
                    ProblemView(text: problem, offline: offline) { tries += 1 }
                    // your liked songs play offline: the ones that match, here
                    let mine = liked.filter { matches($0, asked) }
                    if !mine.isEmpty { songList(mine, title: "In your liked songs") { i in app.player.play(mine, i) } }
                }
            } else if list.isEmpty {
                Note("Nothing found for “\(asked)”.")
            } else {
                let mine = liked.filter { matches($0, asked) }
                let all = mine + list.filter { r in !mine.contains { $0.key == r.key } }
                List {
                    ForEach(all, id: \.key) { t in
                        TrackRow(track: t, onPlay: { app.player.playWithRelated(t) }) {
                            QualityBadge(track: t)
                            HeartButton(track: t)
                        }
                        .listRowBackground(Brand.night)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        } else {
            let mine = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : liked.filter { matches($0, query) }
            if mine.isEmpty {
                Note("Lossless FLAC from the Internet Archive comes first; YouTube Music when it's not there. Like a song and it's saved on your iPhone (Files → Radiance Music).")
            } else {
                ScrollView { songList(mine, title: "In your liked songs") { i in app.player.play(mine, i) } }
            }
        }
    }

    private func songList(_ songs: [Track], title: String, onPlay: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title).padding(.bottom, 4)
            ForEach(Array(songs.enumerated()), id: \.element.key) { i, t in
                TrackRow(track: t, onPlay: { onPlay(i) }) { HeartButton(track: t) }
            }
        }
        .padding(.horizontal, 16)
    }

    private func search(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        typing = false
        if asked == q { tries += 1 } else { asked = q } // the same again: it looks again
    }

    private func clear() {
        query = ""
        results = nil
        asked = ""
        problem = nil
        offline = false
        suggestions = []
    }

    private func suggest() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty || q == asked { suggestions = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        let s = await YouTube.suggestions(q)
        if !Task.isCancelled { suggestions = Array(s.prefix(8)) }
    }

    private func look() async {
        let q = asked
        guard !q.isEmpty else { return }
        busy = true
        suggestions = []
        // lossless first: the Internet Archive, then YouTube Music
        async let archive: Result<[Track], Error> = { do { return .success(try await Archive.search(q)) } catch { return .failure(error) } }()
        async let youtube: Result<[Track], Error> = { do { return .success(try await YouTube.search(q)) } catch { return .failure(error) } }()
        let (a, y) = await (archive, youtube)
        if Task.isCancelled { return }
        let found = ((try? a.get()) ?? []) + ((try? y.get()) ?? [])
        let failed: Error? = { if case .failure(let e) = y { return e }; if case .failure(let e) = a { return e }; return nil }()
        offline = found.isEmpty && !app.online
        if !found.isEmpty { problem = nil }
        else if offline { problem = "You're offline. Connect to search." }
        else if let failed { problem = "Couldn't search. \(Errors.say(failed, online: app.online))" }
        else { problem = nil }
        results = found
        busy = false
        if let n = app.test["RM_PLAY"].flatMap(Int.init), q == app.test["RM_SEARCH"] {
            let mine = app.library.liked.filter { matches($0, q) }
            let all = mine + found.filter { r in !mine.contains { $0.key == r.key } }
            if all.indices.contains(n) { app.player.playWithRelated(all[n]) }
        }
    }
}
