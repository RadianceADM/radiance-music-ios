import RadianceKit
import SwiftUI

/** Settings (stage 1): your servers (YouTube songs play through one), the look, and About. */
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var invite = ""
    @State private var joining = false
    @State private var joinProblem: String?
    @State private var sharing = false
    /** A share QR the Camera app read (radiancemusic://share?…): the share starts with it. */
    @State private var shareLink: String?
    /** A server's invite from a link: asked before joining. */
    @State private var asking: String?
    @State private var guide = false
    @State private var olderNews = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    ForEach(app.servers.list) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name).font(.system(size: 16, weight: .semibold))
                            Text(health(s)).font(.system(size: 13)).foregroundStyle(Brand.dim)
                        }
                        .swipeActions {
                            Button("Leave", role: .destructive) { Task { try? await app.servers.leave(s) } }
                        }
                    }
                    TextField("Paste an invite: https://…/join/…", text: $invite, axis: .vertical)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    if let joinProblem { Text(joinProblem).font(.system(size: 13)).foregroundStyle(Brand.heart) }
                    Button {
                        join()
                    } label: {
                        HStack { Label("Join", systemImage: "person.badge.plus"); if joining { Spacer(); ProgressView() } }
                    }
                    .disabled(invite.trimmingCharacters(in: .whitespaces).isEmpty || joining)
                } header: {
                    Text("Servers")
                } footer: {
                    Text("A Radiance Music Server shares its songs with you. A YouTube song plays from a server you joined when it has it, else from YouTube.")
                }
                Section {
                    Button { sharing = true } label: { Label("Share songs by QR", systemImage: "qrcode") }
                    Button { app.findSaved(auto: false) } label: { Label("Bring back songs in Files → Radiance Music", systemImage: "arrow.clockwise") }
                } header: { Text("Your songs") }
                Section {
                    Button { guide = true } label: { Label("How to use it", systemImage: "questionmark.circle") }
                } header: { Text("Help") }
                Section("Look") {
                    Picker("Colours", selection: $app.stone) {
                        Text("True Black").tag(false)
                        Text("Stone").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                whatsNew
                Section {
                    Button { openURL(URL(string: Links.mail(version: About.version))!) } label: {
                        LabeledContent { Text(Links.email).foregroundStyle(Brand.dim) } label: { Label("Email us", systemImage: "envelope") }
                    }
                    Button { openURL(URL(string: Links.site)!) } label: {
                        LabeledContent { Text("for your computer").foregroundStyle(Brand.dim) } label: { Label("music.radianceph.com", systemImage: "globe") }
                    }
                } header: { Text("Tell us what breaks") } footer: {
                    Text("What you did, and what happened. A screenshot helps.")
                }
                Section("About") {
                    LabeledContent("Version", value: About.version)
                    if let until = About.expires {
                        LabeledContent("This copy opens until", value: until.formatted(date: .abbreviated, time: .shortened))
                    }
                    Text("© Radiance Innovation Centers in the Philippines. All rights reserved.")
                        .font(.system(size: 13)).foregroundStyle(Brand.dim)
                    Text("Lossless songs from the Internet Archive, lyrics from LRCLIB, genres from Deezer. Splitting: Spleeter (Deezer, MIT License), its models exported by sherpa-onnx (Apache License 2.0), run on ONNX Runtime (Microsoft, MIT License).")
                        .font(.system(size: 13)).foregroundStyle(Brand.dim)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.sheet)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $sharing, onDismiss: { shareLink = nil }) { ShareScreen(opened: shareLink) }
            .fullScreenCover(isPresented: $guide) { GuideScreen { Guide.seen(); guide = false } }
            .alert("Join this server?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), presenting: asking) { link in
                Button("Join") { invite = link; asking = nil; join() }
                Button("Not now", role: .cancel) { asking = nil }
            } message: { link in
                Text("\(Servers.invite(link).map { $0.base.components(separatedBy: "://").last ?? $0.base } ?? "A server") invited this iPhone. It shares its songs with you.")
            }
            .onAppear(perform: take)
            .onChange(of: app.opening) { take() }
        }
    }

    /** A link that opened the app: an invite is asked about, a share QR starts the share. */
    private func take() {
        guard let o = app.opening else { return }
        app.opening = nil
        switch o {
        case .invite(let link): asking = link
        case .share(let link): shareLink = link; sharing = true
        }
    }

    /** What's new in this version, from the changelog that comes with the app; earlier ones on a tap. */
    @ViewBuilder private var whatsNew: some View {
        if let news = About.news.first {
            Section {
                ForEach(news.items, id: \.self) { Bullet(text: $0) }
                if olderNews {
                    ForEach(About.news.dropFirst().prefix(4), id: \.version) { r in
                        Text(r.version).font(.system(size: 15, weight: .semibold))
                        ForEach(r.items, id: \.self) { Bullet(text: $0) }
                    }
                }
                if About.news.count > 1 {
                    Button { withAnimation { olderNews.toggle() } } label: {
                        Label(olderNews ? "Fewer" : "Earlier versions", systemImage: olderNews ? "chevron.up" : "chevron.down")
                    }
                }
            } header: { Text("What's new in \(news.version)") }
        }
    }

    private func health(_ s: Server) -> String {
        switch app.servers.health[s.base] ?? .unknown {
        case .unknown: return s.host
        case .answering: return "\(s.host) · connected"
        case .down(let why, _): return why
        case .removed(let why): return why
        }
    }

    private func join() {
        joining = true
        joinProblem = nil
        Task {
            defer { joining = false }
            do {
                let s = try await app.servers.join(invite, deviceName: AppModel.deviceName)
                invite = ""
                app.tell("Joined \(s.name).")
            } catch {
                joinProblem = (error as? Refused)?.words ?? (error as? Plain)?.words ?? Errors.say(error, online: app.online)
            }
        }
    }
}

/** The version, and when this free-signed copy stops opening (the date in its embedded.mobileprovision). */
enum About {
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    /** The changelog that comes with the app, newest first. */
    static let news: [Changelog.Release] = {
        guard let url = Bundle.module.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Changelog.releases(text)
    }()

    static let expires: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        // a signed plist: the XML sits in the middle, as text
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>") else { return nil }
        let plist = Data(text[start.lowerBound..<end.upperBound].utf8)
        let o = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        return o?["ExpirationDate"] as? Date
    }()
}

/** A changelog item: a dot, its words (**bold** as bold). */
struct Bullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(Brand.orange)
            Text((try? AttributedString(markdown: text)) ?? AttributedString(text)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.86))
        }
    }
}
