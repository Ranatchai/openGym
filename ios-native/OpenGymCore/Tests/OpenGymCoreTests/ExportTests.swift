import Foundation
import OpenGymCore
import XCTest

enum ExportFiles {
    static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../../..")
        .standardized
    static let resources = repo.appending(path: "ios-native/OpenGymApp/Resources")
    static let exercises = resources.appending(path: "exercises.json")
    static let strings = resources.appending(path: "Localizable.xcstrings")
    static let muscleOverlays = [
        "exercise-muscle-batch-1.json",
        "exercise-muscle-batch-2.json",
        "exercise-muscle-olympic.json",
    ].map { repo.appending(path: "frontend/src/lib/\($0)") }
}

struct StringCatalog: Decodable {
    struct Entry: Decodable {
        let extractionState: String
        let localizations: [String: Localization]
    }
    struct Localization: Decodable {
        struct StringUnit: Decodable {
            let state: String
            let value: String
        }
        let stringUnit: StringUnit
    }
    let sourceLanguage: String
    let strings: [String: Entry]
    let version: String
}

struct MuscleOverlay: Decodable {
    let bp: String?
    let primaries: [String]
    let secondaries: [String]
}

final class ExportTests: XCTestCase {
    static let languages = [
        "ar", "de", "de-CH", "es", "fr", "hi", "hu", "it", "ko",
        "pl", "pt", "pt-BR", "ru", "th", "tr", "uk", "zh",
    ]

    func testCatalogue() throws {
        let catalogue = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: ExportFiles.exercises))
        let byId = Dictionary(uniqueKeysWithValues: catalogue.map { ($0.id, $0) })
        XCTAssertEqual(catalogue.count, 1324)
        XCTAssertEqual(byId.count, 1324)

        let deadlift = try XCTUnwrap(byId["1010"])
        XCTAssertEqual(deadlift.bp, "upper legs")
        XCTAssertEqual(deadlift.primaries, ["gluteal", "hamstring"])
        XCTAssertEqual(deadlift.secondaries, ["lower-back", "quadriceps", "adductors", "calves"])
        let calfRaise = try XCTUnwrap(byId["1253"])
        XCTAssertEqual(calfRaise.primaries, ["calves"])
        XCTAssertEqual(calfRaise.secondaries, [])
        let snatch = try XCTUnwrap(byId["3888"])
        XCTAssertEqual(snatch.bp, "full body")
        XCTAssertEqual(snatch.primaries, ["quadriceps", "gluteal", "hamstring", "trapezius", "deltoids"])

        var overlay: [String: MuscleOverlay] = [:]
        for file in ExportFiles.muscleOverlays {
            let layer = try JSONDecoder().decode([String: MuscleOverlay].self, from: Data(contentsOf: file))
            overlay.merge(layer) { _, later in later }
        }
        for (id, muscles) in overlay {
            let exercise = try XCTUnwrap(byId[id], "overlay id \(id) missing from the catalogue")
            XCTAssertEqual(exercise.primaries, muscles.primaries, id)
            XCTAssertEqual(exercise.secondaries, muscles.secondaries, id)
            if let bp = muscles.bp { XCTAssertEqual(exercise.bp, bp, id) }
        }
        XCTAssertEqual(catalogue.filter { $0.primaries != nil }.count, overlay.count)
        print("ExportTests.testCatalogue: \(catalogue.count) exercises, \(overlay.count) with muscle overlays")
    }

    func testStringCatalog() throws {
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: ExportFiles.strings))
        XCTAssertEqual(catalog.sourceLanguage, "en")
        XCTAssertEqual(catalog.strings.count, 1704)

        let args = ["\u{1}A", "\u{1}B", "\u{1}C"]
        func placeholders(_ format: String) -> [String] {
            format.matches(of: /%(\d)\$@/).map { String($0.output.1) }.sorted()
        }
        var checked = 0
        for (key, entry) in catalog.strings {
            XCTAssertEqual(entry.extractionState, "manual", key)
            XCTAssertEqual(Set(entry.localizations.keys).subtracting(["en"]), Set(Self.languages), key)
            let source = entry.localizations["en"]?.stringUnit.value ?? key
            var expected = key
            for (i, arg) in args.enumerated() { expected = expected.replacing("{\(i)}", with: arg) }
            XCTAssertEqual(String(format: source, arguments: args), expected, key)

            for lang in Self.languages {
                let unit = try XCTUnwrap(entry.localizations[lang]?.stringUnit, "\(lang): \(key)")
                XCTAssertEqual(unit.state, "translated")
                XCTAssertEqual(placeholders(unit.value), placeholders(source), "\(lang): \(key)")
                XCTAssertFalse(unit.value.contains(/\{\d+\}/), "\(lang): \(key)")
                if lang == "de-CH" { XCTAssertFalse(unit.value.contains("ß"), key) }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 1704 * Self.languages.count)
        print("ExportTests.testStringCatalog: \(catalog.strings.count) keys x \(Self.languages.count) languages, \(checked) translations with placeholder parity")
    }
}
