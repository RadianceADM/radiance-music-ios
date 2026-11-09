import SwiftUI

/**
 * Radiance's colours (Android's ui/Theme.kt): True Black (the default) or Stone, warm greys. No navy (owner,
 * 2026-10-29: "wag navy blue … either stone or true black lang").
 */
enum Brand {
    static var stone: Bool { UserDefaults.standard.bool(forKey: "look.stone") }

    /** The screen itself. */
    static var night: Color { stone ? Color(hex: 0x1C1917) : Color(hex: 0x000000) }
    /** Sheets over it. */
    static var sheet: Color { stone ? Color(hex: 0x0C0A09) : Color(hex: 0x121212) }
    /** Cards, fields, pills. */
    static var card: Color { stone ? Color(hex: 0x292524) : Color(hex: 0x1C1C1E) }
    /** Quiet words. */
    static var dim: Color { stone ? Color(hex: 0xA8A29E) : Color(hex: 0x9A9A9F) }
    static var line: Color { stone ? Color(hex: 0x44403C) : Color(hex: 0x2C2C2E) }
    static let orange = Color(hex: 0xF38A35)
    static let glow = Color(hex: 0xFFAE63)
    static let heart = Color(hex: 0xE5364F)
    static let lossless = Color(hex: 0x8FF0A4)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/** The Home banner's sunset: soft orange lights on the dark, as on Android. */
struct Sunset: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3A1A06), Color(hex: 0x120804)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Brand.orange.opacity(0.55), .clear], center: UnitPoint(x: 0.85, y: 1.05), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Brand.glow.opacity(0.30), .clear], center: UnitPoint(x: 0.1, y: 0.0), startRadius: 0, endRadius: 220)
        }
    }
}
