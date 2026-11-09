import RadianceKit
import SwiftUI

/**
 * A song as a story (1080 × 1920, what Instagram and Facebook stories are; Android's share/StoryCard.kt): its cover
 * big on a soft blur of itself, the title and who sings it; or, with lyrics picked, the lines big on a rounded card
 * with the cover small above them. Soft all over; everything stays between the stories' top and bottom bars.
 */
struct StoryCard: View {
    let track: Track
    let cover: UIImage?
    var lyrics: String? = nil

    static let size = CGSize(width: 1080, height: 1920)

    var body: some View {
        ZStack {
            Color.black
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill().frame(width: 1080, height: 1920).blur(radius: 70).clipped()
                Color.black.opacity(0.45)
            } else {
                LinearGradient(colors: [Color(hex: 0x7A3410), Color(hex: 0x292524)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            VStack(spacing: 0) {
                Spacer().frame(height: 250)
                if let lyrics, !lyrics.isEmpty {
                    VStack(alignment: .leading, spacing: 36) {
                        HStack(spacing: 28) {
                            art(170, corner: 24)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(track.title).font(.system(size: 50, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                                Text(track.artist).font(.system(size: 40)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                            }
                        }
                        Text(lyrics).font(.system(size: 74, weight: .heavy)).foregroundStyle(.white).lineSpacing(10)
                            .minimumScaleFactor(0.5).lineLimit(7)
                    }
                    .padding(64)
                    .frame(width: 940, alignment: .leading)
                    .background(Color(hex: 0xF38A35).opacity(0.92), in: RoundedRectangle(cornerRadius: 60, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
                } else {
                    art(860, corner: 56).shadow(color: .black.opacity(0.5), radius: 50, y: 24)
                    Spacer().frame(height: 80)
                    Text(track.title).font(.system(size: 76, weight: .heavy)).foregroundStyle(.white).lineLimit(2)
                        .multilineTextAlignment(.center).frame(width: 940)
                    Text(track.artist).font(.system(size: 50)).foregroundStyle(.white.opacity(0.8)).lineLimit(1).padding(.top, 14)
                }
                Spacer()
                HStack(spacing: 18) {
                    Image(systemName: "waveform").font(.system(size: 44, weight: .bold)).foregroundStyle(Color(hex: 0xF38A35))
                    Text("Radiance Music").font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                }
                Spacer().frame(height: 330)
            }
        }
        .frame(width: StoryCard.size.width, height: StoryCard.size.height)
    }

    private func art(_ side: CGFloat, corner: CGFloat) -> some View {
        Group {
            if let cover { Image(uiImage: cover).resizable().scaledToFill() }
            else { Color(hex: 0x292524).overlay(Image(systemName: "music.note").font(.system(size: side * 0.35)).foregroundStyle(.white.opacity(0.4))) }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    /** The card as a picture, to share. */
    @MainActor
    static func render(_ t: Track, cover: UIImage?, lyrics: String?) -> UIImage? {
        let r = ImageRenderer(content: StoryCard(track: t, cover: cover, lyrics: lyrics))
        r.scale = 1
        return r.uiImage
    }
}

/**
 * Share a song (Android's ShareSheet): its story card with the Cover, or with Lyrics (the lines you pick, next to each
 * other, 150 characters at most), to Instagram, Facebook, Messenger or anywhere.
 */
struct ShareSongSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let track: Track
    /** A line held in the lyrics: it comes picked. */
    var lyrics: String? = nil
    @State private var withLyrics = false
    @State private var lines: [String]?
    @State private var picked: [Int] = []
    @State private var choosing = false
    @State private var cover: UIImage?
    @State private var card: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let card {
                    Image(uiImage: card).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 48)
                } else {
                    ProgressView().tint(Brand.orange).controlSize(.large).frame(maxHeight: .infinity)
                }
                HStack(spacing: 10) {
                    chip("Cover", "photo", !withLyrics) { withLyrics = false; draw() }
                    chip("Lyrics", picked.isEmpty || !withLyrics ? "quote.opening" : "pencil", withLyrics) {
                        if withLyrics || picked.isEmpty { choosing = true } else { withLyrics = true; draw() }
                    }
                }
                if let card {
                    ShareLink(item: Image(uiImage: card), preview: SharePreview("\(track.title) · \(track.artist)", image: Image(uiImage: card))) {
                        Label("Share", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 40)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.sheet)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $choosing, onDismiss: {
                withLyrics = !picked.isEmpty
                draw()
            }) {
                ChooseLyrics(lines: lines, picked: $picked)
            }
        }
        .task {
            cover = await app.covers.image(track, px: Art.big)
            let found = await Saver.lyrics(app.paths, track)
            switch found {
            case .timed(let l): lines = l.map { $0.text.trimmingCharacters(in: .whitespaces) }
            case .plain(let text): lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case .none: lines = []
            }
            // a line held in the lyrics comes picked
            if let held = lyrics?.trimmingCharacters(in: .whitespaces), let i = lines?.firstIndex(of: held) { picked = [i]; withLyrics = true }
            draw()
        }
    }

    private func chip(_ label: String, _ icon: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon).labelStyle(.titleAndIcon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? .black : .white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(on ? Color.white : Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func draw() {
        let text = withLyrics ? picked.sorted().compactMap { lines?.indices.contains($0) == true ? lines![$0] : nil }.joined(separator: "\n") : nil
        card = StoryCard.render(track, cover: cover, lyrics: text)
    }
}

/** Choose lyrics (Android's): tap lines to pick them, next to each other, 150 characters at most. */
struct ChooseLyrics: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let lines: [String]?
    @Binding var picked: [Int]
    @State private var say: String?

    var body: some View {
        NavigationStack {
            Group {
                if let lines, !lines.isEmpty {
                    List {
                        if let say { Text(say).font(.system(size: 13)).foregroundStyle(Brand.glow).listRowBackground(Brand.sheet) }
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            let on = picked.contains(i)
                            Text(line.isEmpty ? "♪" : line)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(on ? .black : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8).padding(.horizontal, 12)
                                .background(on ? Brand.orange : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                                .onTapGesture { say = LyricPick.tap(&picked, i, lines.map(\.count)) }
                                .listRowBackground(Brand.sheet)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else if lines == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Note(app.online ? "No lyrics found for this song." : "You're offline. Connect to pick lyrics.")
                }
            }
            .background(Brand.sheet)
            .navigationTitle("Choose lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let used = picked.reduce(0) { $0 + (lines?.indices.contains($1) == true ? lines![$1].count : 0) }
                    Text("\(used)/\(LyricPick.most)").font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(used >= LyricPick.most - 10 ? Brand.glow : .white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.disabled(picked.isEmpty) }
            }
        }
    }
}
