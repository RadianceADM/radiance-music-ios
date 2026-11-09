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

/** Share a song: its story card (with a lyric line, if one was picked), to Instagram, Facebook, Messenger or anywhere. */
struct ShareSongSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let track: Track
    var lyrics: String? = nil
    @State private var card: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let card {
                    Image(uiImage: card).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 40)
                    ShareLink(item: Image(uiImage: card), preview: SharePreview("\(track.title) · \(track.artist)", image: Image(uiImage: card))) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 40)
                } else {
                    ProgressView().tint(Brand.orange).controlSize(.large).frame(maxHeight: .infinity)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.sheet)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task {
            let cover = await app.covers.image(track, px: Art.big)
            card = StoryCard.render(track, cover: cover, lyrics: lyrics)
        }
    }
}
