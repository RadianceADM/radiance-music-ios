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
                        HStack { Text("Join"); if joining { Spacer(); ProgressView() } }
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
                Section("Look") {
                    Picker("Colours", selection: $app.stone) {
                        Text("True Black").tag(false)
                        Text("Stone").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section("About") {
                    LabeledContent("Version", value: About.version)
                    if let until = About.expires {
                        LabeledContent("This copy opens until", value: until.formatted(date: .abbreviated, time: .shortened))
                    }
                    Text("Radiance Music is free software (GPL-3.0). Lossless songs from the Internet Archive, lyrics from LRCLIB, genres from Deezer.")
                        .font(.system(size: 13)).foregroundStyle(Brand.dim)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.sheet)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $sharing) { ShareScreen() }
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
