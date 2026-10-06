import Foundation
import Testing
import OpenGymCore

@Suite struct ConformanceTests {
    @Test func testWorkoutModel() throws {
        try checkConformance(module: "workout-model")
    }

    @Test func testRepRange() throws {
        try checkConformance(module: "rep-range")
    }
}

private let reportedPerFunction = 5

func checkConformance(module: String) throws {
    guard let url = Bundle.module.url(forResource: module, withExtension: "json", subdirectory: "Fixtures/conformance") else {
        Issue.record("Fixtures/conformance/\(module).json is missing; run node ios-native/tools/gen-fixtures.mjs")
        return
    }
    let fixture = try JSONParser.parse(Array(try Data(contentsOf: url)))
    guard let ports = ConformanceRegistry.modules[module] else {
        Issue.record("no Swift ports registered for \(module)")
        return
    }
    let exports = fixture.objectValue?["exports"]?.arrayValue?.compactMap(\.stringValue) ?? []
    let calls = fixture.objectValue?["calls"]?.arrayValue ?? []
    for name in exports where ports[name] == nil {
        Issue.record("no Swift port registered for \(module).\(name)")
    }
    for name in ports.keys where !exports.contains(name) {
        Issue.record("\(module).\(name) is registered but is not a JS export")
    }

    var passed: [String: Int] = [:]
    var failed: [String: Int] = [:]
    for call in calls {
        let record = call.objectValue ?? JSONObject()
        let name = record["fn"]?.stringValue ?? "?"
        guard let port = ports[name] else { continue }
        let argsText = JSONSerializer.string(record["args"] ?? .null)
        let problem = mismatch(port, record)
        if let problem {
            failed[name, default: 0] += 1
            if failed[name, default: 0] <= reportedPerFunction {
                Issue.record("\(module).\(name)(\(argsText.dropFirst().dropLast())): \(problem)")
            }
        } else {
            passed[name, default: 0] += 1
        }
    }
    for (name, count) in failed.sorted(by: { $0.key < $1.key }) where count > reportedPerFunction {
        Issue.record("\(module).\(name): \(count) calls differ in all, the first \(reportedPerFunction) are listed")
    }
    let total = passed.values.reduce(0, +)
    print("ConformanceTests: \(module) \(total)/\(calls.count) recorded calls pass across \(passed.count) functions")
    for name in exports {
        print("  \(module).\(name): \(passed[name, default: 0]) pass, \(failed[name, default: 0]) fail")
    }
    #expect(total == calls.count && !calls.isEmpty)
}

private func mismatch(_ port: Port, _ record: JSONObject) -> String? {
    let args: Args
    do {
        args = try FixtureValue.args(record["args"] ?? .null)
    } catch {
        return "fixture not representable in Swift: \(error)"
    }
    let outcome: String
    let swiftThrew: Bool
    do {
        outcome = JSONSerializer.string(FixtureValue.encode(try port(args)))
        swiftThrew = false
    } catch let error as JSTypeError {
        outcome = error.message
        swiftThrew = true
    } catch {
        return "\(error)"
    }
    for replay in args.replays.values {
        if let miss = replay.misses.first { return miss }
        if replay.used != replay.calls.count { return "Swift called the callback \(replay.used) times, JS \(replay.calls.count)" }
    }
    if case .string(let message)? = record["throws"] {
        if swiftThrew, outcome == message { return nil }
        return "JS threw \"\(message)\", Swift \(swiftThrew ? "threw \"\(outcome)\"" : "returned \(outcome)")"
    }
    let expected = JSONSerializer.string(record["result"] ?? .null)
    if !swiftThrew, outcome == expected { return nil }
    return "JS \(expected), Swift \(swiftThrew ? "threw \"\(outcome)\"" : outcome)"
}
