import OSLog
import RadianceKit
import SwiftUI
import UIKit

/** What the report sends from this iPhone: the version, the iPhone and its iOS, this install's id, the app's log. */
enum ReportLog {
    @MainActor
    static func gather() async -> Report.What {
        let system = "iOS \(UIDevice.current.systemVersion), \(AppModel.model)"
        let log = await Task.detached(priority: .utility) { Report.newest(Report.scrub(ownLog()), Report.mostLog) }.value
        return Report.What(version: About.version, system: system, install: Report.installId(), log: log)
    }

    /**
     * The app's lines in the iPhone's log, this run's (an app reads only its own): its own (Log.say), and anything
     * that went wrong in it (errors and faults), not the system's chatter.
     */
    nonisolated static func ownLog() -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(at: store.position(timeIntervalSinceLatestBoot: 0)) else { return "" }
        let clock = DateFormatter()
        clock.dateFormat = "MM-dd HH:mm:ss.SSS"
        var lines: [String] = []
        for case let e as OSLogEntryLog in entries {
            let ours = e.subsystem == "io.github.radianceadm.music"
            guard ours || e.level == .error || e.level == .fault else { continue }
            let mark = e.level == .fault ? "F" : e.level == .error ? "E" : "I"
            lines.append("\(clock.string(from: e.date)) \(mark)/\(ours ? "RadianceMusic" : e.subsystem): \(e.composedMessage)")
        }
        return lines.suffix(4000).joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }
}

/**
 * Settings → Report a problem (Android's ReportSheet): what will be sent, shown in full before anything goes; an
 * optional note; Send. Then the report's code to quote, with Copy.
 */
struct ReportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var what: Report.What?
    @State private var showing = false
    @State private var sending = false
    @State private var problem: String?
    @State private var sent: String?

    var body: some View {
        NavigationStack {
            Group {
                if let sent {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Brand.lossless)
                        Text("Sent. Thank you!").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        Text("Your report is \(sent). If you write to us about it (\(Links.email)), quote that.")
                            .font(.system(size: 15)).foregroundStyle(Brand.dim).multilineTextAlignment(.center)
                        Button { UIPasteboard.general.string = sent; app.tell("Copied \(sent).") } label: {
                            Label("Copy the code", systemImage: "doc.on.doc").labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered).tint(.white)
                        Button { dismiss() } label: { Label("Close", systemImage: "xmark").labelStyle(.titleAndIcon) }.tint(Brand.dim)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section {
                            TextField("What you did, and what happened (you can leave it empty)", text: $note, axis: .vertical)
                                .lineLimit(4...10)
                                .onChange(of: note) { _, n in if n.count > Report.mostNote { note = String(n.prefix(Report.mostNote)) } }
                        } header: {
                            Text("Tell us what went wrong. Nothing is sent until you press Send, and you can see below exactly what goes.")
                                .textCase(nil)
                        } footer: {
                            if !note.isEmpty { Text("\(note.count) of \(Report.mostNote)") }
                        }
                        Section {
                            DisclosureGroup(isExpanded: $showing) {
                                Text(what?.shown() ?? "Reading the app's log…")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                                    .textSelection(.enabled)
                            } label: { Label("What will be sent", systemImage: "doc.text.magnifyingglass") }
                        }
                        if let problem {
                            Section { Text(problem).font(.system(size: 14)).foregroundStyle(Brand.orange) }
                        }
                        Section {
                            Button { send() } label: {
                                HStack {
                                    Label("Send", systemImage: "paperplane.fill")
                                    if sending { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(what == nil || sending)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Brand.sheet)
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sent == nil {
                    ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("Cancel", systemImage: "xmark") } }
                }
            }
            .task { what = await ReportLog.gather() }
        }
    }

    private func send() {
        guard let what else { return }
        sending = true
        problem = nil
        Task {
            defer { sending = false }
            do {
                sent = try await Report.send(what.body(note))
            } catch {
                problem = (error as? Plain)?.words ?? "Couldn't send it. \(Errors.say(error, online: app.online))"
            }
        }
    }
}
