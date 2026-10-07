import XCTest
@testable import OpenGymApp

final class AppLanguageTests: XCTestCase {
    private struct Case: Decodable {
        let tag: String
        let match: String?
    }

    func testMatchesTheWebMatchLocale() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "match-locale", withExtension: "json"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(cases.count, 30)
        for c in cases {
            XCTAssertEqual(AppLanguage.match(c.tag), c.match, "matchLocale(\(c.tag.debugDescription))")
        }
    }

    func testTraditionalChineseResolvesToChinese() {
        XCTAssertEqual(AppLanguage.resolve(["zh-Hant-TW", "en-US"]), "zh")
        XCTAssertEqual(AppLanguage.resolve(["ja-JP", "pt-PT"]), "pt")
        XCTAssertEqual(AppLanguage.resolve(["ja-JP"]), "en")
    }

    func testLooksUpTheResolvedLanguage() {
        XCTAssertEqual(AppLanguage(code: "th")("Home"), "หน้าหลัก")
        XCTAssertEqual(AppLanguage(code: "zh")("{0} exercises", "6"), "6 个动作")
        XCTAssertEqual(AppLanguage(code: "de-CH")("Home"), AppLanguage(code: "de")("Home"))
    }

    func testLiteralPercentSurvivesTheFormatPass() {
        XCTAssertEqual(AppLanguage(code: "en")("Deload 1RM (%)"), "Deload 1RM (%)")
    }

    func testUnknownKeyFallsBackToItself() {
        XCTAssertEqual(AppLanguage(code: "th")("openGym"), "openGym")
    }

    func testArabicIsRightToLeft() {
        XCTAssertEqual(AppLanguage(code: "ar").layoutDirection, .rightToLeft)
        XCTAssertEqual(AppLanguage(code: "th").layoutDirection, .leftToRight)
    }
}
