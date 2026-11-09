import RadianceKit
import SwiftUI

/** A song's cover at [size] points: the kept one first, else its address at the size it's drawn; a soft tile when there's none. */
struct CoverView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var scale
    let track: Track
    var size: CGFloat = 48
    var corner: CGFloat = 10
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Brand.card, Brand.line], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(Brand.dim)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: "\(track.key)|\(track.art)|\(Int(size))") {
            let px = Int(size * scale)
            image = app.covers.cached(track, px: px)
            if image == nil { image = await app.covers.image(track, px: px) }
        }
    }
}

/** Lossless (the Internet Archive's FLAC) or the kind of file it is. */
struct QualityBadge: View {
    let track: Track
    var body: some View {
        if track.lossless || track.format.contains("FLAC") {
            Text(track.format.contains("24") ? "Hi-Res" : "Lossless")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.lossless)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Brand.lossless.opacity(0.14), in: Capsule())
        }
    }
}

/** Like it (it's saved on the iPhone), or not. */
struct HeartButton: View {
    @Environment(AppModel.self) private var app
    let track: Track
    var size: CGFloat = 20

    var body: some View {
        let liked = app.isLiked(track)
        Button {
            app.toggleLike(track)
        } label: {
            ZStack {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(liked ? Brand.heart : Brand.dim)
                if let p = app.saving[track.key] {
                    Circle().trim(from: 0, to: max(0.05, p)).stroke(Brand.orange, lineWidth: 2)
                        .rotationEffect(.degrees(-90)).frame(width: size + 14, height: size + 14)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(liked ? "Unlike" : "Like")
    }
}

/** One song in a list: its cover, title and who's on it; tap to play; hold for more. */
struct TrackRow<Trailing: View>: View {
    @Environment(AppModel.self) private var app
    let track: Track
    let onPlay: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let isCurrent = app.player.current?.key == track.key
        HStack(spacing: 12) {
            CoverView(track: track, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isCurrent ? Brand.orange : .white).lineLimit(1)
                Text([track.byline(), track.seconds > 0 ? clock(track.seconds) : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(Brand.dim).lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .contextMenu { SongMenu(track: track) }
    }
}

extension TrackRow where Trailing == EmptyView {
    init(track: Track, onPlay: @escaping () -> Void) {
        self.init(track: track, onPlay: onPlay, trailing: { EmptyView() })
    }
}

/** A song's menu: play it next, add it to the queue, songs like it, like it. */
struct SongMenu: View {
    @Environment(AppModel.self) private var app
    let track: Track

    var body: some View {
        Button { app.player.playNext(track) } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { app.player.enqueue(track) } label: { Label("Add to queue", systemImage: "text.badge.plus") }
        Button { app.player.radio(track) } label: { Label("Songs like this", systemImage: "dot.radiowaves.left.and.right") }
        Button { app.toggleLike(track) } label: {
            app.isLiked(track) ? Label("Unlike", systemImage: "heart.slash") : Label("Like", systemImage: "heart")
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/** Quiet words where there's nothing yet. */
struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Brand.dim).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(28)
    }
}

/** Why something couldn't happen, in plain words, with Try again. */
struct ProblemView: View {
    let text: String
    var offline = false
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: offline ? "wifi.slash" : "exclamationmark.circle").font(.system(size: 28)).foregroundStyle(Brand.dim)
            Text(text).font(.system(size: 15)).foregroundStyle(.white).multilineTextAlignment(.center)
            Button("Try again", action: onRetry).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity).padding(28)
    }
}

/** A big title with Settings beside it, as each tab starts on Android. */
struct PageTitle: View {
    let title: String
    let onSettings: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.system(size: 34, weight: .heavy)).tracking(-1).foregroundStyle(.white)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Brand.card, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
    }
}
