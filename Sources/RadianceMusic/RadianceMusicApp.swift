import RadianceKit
import SwiftUI

/** Radiance Music for iPhone and iPad (stage 0: the app opens, in Radiance's colours, with its version). */
@main
struct RadianceMusicApp: App {
    var body: some Scene {
        WindowGroup {
            FirstScreen()
                .preferredColorScheme(.dark)
                .tint(Brand.orange)
        }
    }
}

struct FirstScreen: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "Radiance Music \(v) for iPhone"
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5...11: return "Good morning"
        case 12...17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        ZStack {
            Brand.night.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("Home").font(.system(size: 34, weight: .heavy)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 10) {
                    Text(greeting).font(.system(size: 34, weight: .heavy)).tracking(-1).foregroundStyle(.white)
                    Text("Radiance Music is on your iPhone. Search, Library and Now Playing come next.")
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Sunset())
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                Spacer()
                Text(version).font(.footnote).foregroundStyle(Brand.dim).frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }
}
