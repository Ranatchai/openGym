import CoreText
import SwiftUI
import UIKit

struct RGB: Equatable {
    let r: Int, g: Int, b: Int

    var uiColor: UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

/// The five accents of the mockup's AURA table. Light mode tints with `text`, dark mode with
/// `glow`; `deep` is the label colour on a solid tint in dark mode.
enum AuraAccent: String, CaseIterable {
    case orchid, magenta, periwinkle, sky, coral

    var text: RGB {
        switch self {
        case .orchid: RGB(r: 93, g: 56, b: 138)
        case .magenta: RGB(r: 140, g: 56, b: 99)
        case .periwinkle: RGB(r: 64, g: 68, b: 143)
        case .sky: RGB(r: 40, g: 104, b: 144)
        case .coral: RGB(r: 152, g: 93, b: 68)
        }
    }

    var glow: RGB {
        switch self {
        case .orchid: RGB(r: 179, g: 136, b: 231)
        case .magenta: RGB(r: 234, g: 136, b: 186)
        case .periwinkle: RGB(r: 146, g: 150, b: 237)
        case .sky: RGB(r: 117, g: 192, b: 239)
        case .coral: RGB(r: 248, g: 179, b: 150)
        }
    }

    var deep: RGB {
        switch self {
        case .orchid: RGB(r: 44, g: 27, b: 65)
        case .magenta: RGB(r: 67, g: 27, b: 47)
        case .periwinkle: RGB(r: 31, g: 32, b: 68)
        case .sky: RGB(r: 19, g: 50, b: 68)
        case .coral: RGB(r: 72, g: 44, b: 32)
        }
    }

    var tint: Color {
        let light = text.uiColor, dark = glow.uiColor
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    var onTint: Color {
        let dark = deep.uiColor
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : .white })
    }

    /// Debug builds take `-auraAccent <name>` on the launch command line.
    static var launchAccent: AuraAccent {
        #if DEBUG
        UserDefaults.standard.string(forKey: "auraAccent").flatMap(AuraAccent.init(rawValue:)) ?? .orchid
        #else
        .orchid
        #endif
    }
}

extension EnvironmentValues {
    @Entry var auraAccent: AuraAccent = .orchid
}

/// The faint four-blob desk from the mockup's `iosPalette`, one CSS radial-gradient per blob.
struct AuraDesk: View {
    private struct Blob {
        let hue: RGB
        let center: UnitPoint
        let radius: CGSize
        let fade: Double
        let light: Double
        let dark: Double
    }

    private static let blobs = [
        Blob(hue: RGB(r: 150, g: 90, b: 222), center: UnitPoint(x: 0.14, y: 0.10), radius: CGSize(width: 0.55, height: 0.66), fade: 0.60, light: 0.10, dark: 0.14),
        Blob(hue: RGB(r: 226, g: 90, b: 160), center: UnitPoint(x: 0.86, y: 0.18), radius: CGSize(width: 0.52, height: 0.62), fade: 0.62, light: 0.08, dark: 0.09),
        Blob(hue: RGB(r: 245, g: 150, b: 110), center: UnitPoint(x: 0.62, y: 0.06), radius: CGSize(width: 0.50, height: 0.58), fade: 0.60, light: 0.09, dark: 0.06),
        Blob(hue: RGB(r: 64, g: 168, b: 232), center: UnitPoint(x: 0.76, y: 0.92), radius: CGSize(width: 0.60, height: 0.72), fade: 0.64, light: 0.12, dark: 0.12),
    ]

    private static let lightBase = RGB(r: 248, g: 247, b: 250)
    private static let darkBase = RGB(r: 14, g: 13, b: 18)

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(.systemGroupedBackground)
            } else {
                Canvas { context, size in
                    let dark = scheme == .dark
                    let base = dark ? Self.darkBase : Self.lightBase
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(base.uiColor)))
                    for blob in Self.blobs {
                        let color = Color(blob.hue.uiColor).opacity(dark ? blob.dark : blob.light)
                        var ellipse = context
                        ellipse.translateBy(x: blob.center.x * size.width, y: blob.center.y * size.height)
                        ellipse.scaleBy(x: blob.radius.width * size.width, y: blob.radius.height * size.height)
                        ellipse.fill(
                            Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                            with: .radialGradient(
                                Gradient(stops: [.init(color: color, location: 0), .init(color: color.opacity(0), location: blob.fade)]),
                                center: .zero, startRadius: 0, endRadius: 1))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

enum AuraTheme {
    static let largeTitleFontName = "ArchivoRoman-Bold"

    /// Registers the bundled Archivo and makes it the large-title font. Scripts Archivo lacks
    /// (Thai, Arabic, Devanagari, Hangul, CJK, Cyrillic) cascade to the system font.
    @MainActor static func installLargeTitleFont() {
        let url = Bundle.main.url(forResource: "Archivo", withExtension: "ttf")!
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let archivo = UIFont(name: largeTitleFontName, size: 34)!
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: archivo),
            .kern: -0.68,
        ]
    }
}

extension View {
    /// Figures (weights, reps, counts) keep their width as they change.
    func auraData() -> some View {
        monospacedDigit()
    }
}

struct AuraProminentButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.auraAccent) private var accent

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .foregroundStyle(accent.onTint)
    }
}
