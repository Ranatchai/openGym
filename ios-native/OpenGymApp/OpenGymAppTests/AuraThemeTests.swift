import SwiftUI
import UIKit
import XCTest
@testable import OpenGymApp

final class AuraThemeTests: XCTestCase {
    private func rgb(_ color: Color, _ style: UIUserInterfaceStyle) -> [Int] {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b].map { Int(($0 * 255).rounded()) }
    }

    func testAccentTable() {
        let mockup: [AuraAccent: (light: [Int], dark: [Int])] = [
            .orchid: ([93, 56, 138], [179, 136, 231]),
            .magenta: ([140, 56, 99], [234, 136, 186]),
            .periwinkle: ([64, 68, 143], [146, 150, 237]),
            .sky: ([40, 104, 144], [117, 192, 239]),
            .coral: ([152, 93, 68], [248, 179, 150]),
        ]
        XCTAssertEqual(Set(AuraAccent.allCases), Set(mockup.keys))
        for (accent, tint) in mockup {
            XCTAssertEqual(rgb(accent.tint, .light), tint.light, "\(accent) light")
            XCTAssertEqual(rgb(accent.tint, .dark), tint.dark, "\(accent) dark")
        }
    }

    func testLabelOnSolidTint() {
        let deep: [AuraAccent: [Int]] = [
            .orchid: [44, 27, 65], .magenta: [67, 27, 47], .periwinkle: [31, 32, 68],
            .sky: [19, 50, 68], .coral: [72, 44, 32],
        ]
        for (accent, dark) in deep {
            XCTAssertEqual(rgb(accent.onTint, .light), [255, 255, 255], "\(accent) light")
            XCTAssertEqual(rgb(accent.onTint, .dark), dark, "\(accent) dark")
        }
    }

    @MainActor func testArchivoIsBundledAndRegistered() {
        AuraTheme.installLargeTitleFont()
        XCTAssertEqual(UIFont(name: AuraTheme.largeTitleFontName, size: 34)?.familyName, "Archivo")
    }
}
