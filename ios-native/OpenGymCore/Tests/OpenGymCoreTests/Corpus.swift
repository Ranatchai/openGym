import Foundation
import Testing
import OpenGymCore

struct CorpusPair: CustomTestStringConvertible, Sendable {
    let name: String
    let input: [UInt8]
    let expected: [UInt8]

    var testDescription: String { name }
}

struct EditCase: CustomTestStringConvertible, Sendable {
    let name: String
    let input: [UInt8]
    let edit: JSONObject
    let expected: [UInt8]

    var testDescription: String { name }
}

struct MalformedCase: CustomTestStringConvertible, Sendable {
    let name: String
    let input: [UInt8]

    var testDescription: String { name }
}

enum Corpus {
    static let root: URL = {
        guard let url = Bundle.module.url(forResource: "json-corpus", withExtension: nil, subdirectory: "Fixtures") else {
            fatalError("Fixtures/json-corpus is missing; run node ios-native/tools/gen-json-corpus.mjs")
        }
        return url
    }()

    static func subdirectories(_ name: String) -> [URL] {
        let dir = root.appendingPathComponent(name)
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func bytes(_ url: URL) -> [UInt8] {
        guard let data = FileManager.default.contents(atPath: url.path) else { fatalError("missing \(url.path)") }
        return Array(data)
    }

    static func lines(_ url: URL) -> [[UInt8]] {
        bytes(url).split(separator: 0x0A, omittingEmptySubsequences: true).map(Array.init)
    }

    static let pairs: [CorpusPair] = {
        var pairs = subdirectories("cases").map { dir in
            CorpusPair(name: "cases/\(dir.lastPathComponent)",
                       input: bytes(dir.appendingPathComponent("input.json")),
                       expected: bytes(dir.appendingPathComponent("expected.json")))
        }
        let random = root.appendingPathComponent("random")
        let inputs = lines(random.appendingPathComponent("inputs.ndjson"))
        let expected = lines(random.appendingPathComponent("expected.ndjson"))
        precondition(inputs.count == expected.count, "random corpus line counts differ")
        for (i, input) in inputs.enumerated() {
            pairs.append(CorpusPair(name: "random/\(i)", input: input, expected: expected[i]))
        }
        return pairs
    }()

    static let edits: [EditCase] = subdirectories("edits").map { dir in
        let editBytes = bytes(dir.appendingPathComponent("edit.json"))
        guard case .object(let edit) = try? JSONParser.parse(editBytes) else { fatalError("\(dir.path)/edit.json is not an object") }
        return EditCase(name: dir.lastPathComponent,
                        input: bytes(dir.appendingPathComponent("input.json")),
                        edit: edit,
                        expected: bytes(dir.appendingPathComponent("expected.json")))
    }

    static let malformed: [MalformedCase] = {
        let dir = root.appendingPathComponent("malformed")
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { MalformedCase(name: $0.deletingPathExtension().lastPathComponent, input: bytes($0)) }
    }()
}

func firstDifference(_ a: [UInt8], _ b: [UInt8]) -> String {
    let n = min(a.count, b.count)
    var i = 0
    while i < n, a[i] == b[i] { i += 1 }
    if i == n, a.count == b.count { return "identical" }
    let window = { (x: [UInt8]) -> String in
        String(decoding: x[max(0, i - 20)..<min(x.count, i + 40)], as: UTF8.self)
    }
    return "first difference at byte \(i) of \(a.count) vs \(b.count): got …\(window(a))… expected …\(window(b))…"
}
