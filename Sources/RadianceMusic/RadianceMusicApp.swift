import RadianceKit
import SwiftUI

/** Radiance Music for iPhone and iPad. */
@main
struct RadianceMusicApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Brand.orange)
                // a change of look redraws everything
                .id(app.stone)
        }
    }
}
