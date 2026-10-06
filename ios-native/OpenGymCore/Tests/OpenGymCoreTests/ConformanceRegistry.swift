import OpenGymCore

struct NotDrivable: Error, CustomStringConvertible {
    let description: String
}

final class Replay {
    let calls: [(args: [UInt8], result: JSONValue)]
    private(set) var misses: [String] = []
    private(set) var used = 0

    init(_ calls: [(args: [UInt8], result: JSONValue)]) {
        self.calls = calls
    }

    func call(_ x: Double) -> Double {
        let key = JSONSerializer.serialize(FixtureValue.encode(.array([.number(x)])))
        guard used < calls.count, calls[used].args == key else {
            misses.append("callback got (\(JS.numberToString(x))), JS recorded \(used < calls.count ? String(decoding: calls[used].args, as: UTF8.self) : "no further call")")
            return .nan
        }
        defer { used += 1 }
        do {
            return JS.toNumber(try FixtureValue.decodeArgOrResult(calls[used].result))
        } catch {
            misses.append("callback result \(used + 1) is not representable in Swift: \(error)")
            return .nan
        }
    }
}

struct Args {
    let values: [JSONValue?]
    let replays: [Int: Replay]

    subscript(i: Int) -> JSONValue? { i < values.count ? values[i] : nil }

    func number(_ i: Int) -> Double { JS.toNumber(self[i]) }

    func index(_ i: Int) throws -> Int {
        guard case .number(let n) = self[i], n == n.rounded(), let int = Int(exactly: n) else {
            throw NotDrivable(description: "argument \(i) is not an integer index: \(FixtureValue.text(self[i]))")
        }
        return int
    }

    func string(_ i: Int) throws -> String {
        guard case .string(let s) = self[i] else { throw NotDrivable(description: "argument \(i) is not a string") }
        return s
    }

    func side(_ i: Int) -> Side? { Side(self[i]) }

    func grid(_ i: Int) -> DropGrid {
        if let replay = replays[i] { return .snap(replay.call) }
        let step = number(i)
        return step > 0 ? .step(step) : .halfStep
    }

    func phase(_ i: Int) -> SetPhase {
        self[i] == .string("warmup") ? .warmup : .work
    }

    func mode(_ i: Int) -> SetMode {
        guard case .string(let s) = self[i] else { return .reps }
        return SetMode(JSONKey(s)) ?? .reps
    }
}

typealias Port = @Sendable (Args) throws -> JSONValue?

enum ConformanceRegistry {
    static let modules: [String: [String: Port]] = [
        "rep-range": [
            "normalizeRepRange": { a in RepRange.normalize(reps: a[0], repsMin: a[1], stride: a[2]).json },
        ],
        "workout-model": [
            "phaseForSet": { a in .string(WorkoutModel.phaseForSet(a[0], fallback: a.phase(1)).rawValue) },
            "isWarmupRow": { a in .bool(WorkoutModel.isWarmupRow(a[0])) },
            "setType": { a in .string(WorkoutModel.setType(a[0]).rawValue) },
            "isDropSet": { a in .bool(WorkoutModel.isDropSet(a[0])) },
            "isRestPauseSet": { a in .bool(WorkoutModel.isRestPauseSet(a[0])) },
            "dropsOf": { a in .array(WorkoutModel.dropsOf(a[0])) },
            "clustersOf": { a in .array(WorkoutModel.clustersOf(a[0])) },
            "extraVolumeOf": { a in .number(WorkoutModel.extraVolumeOf(a[0])) },
            "addDrop": { a in WorkoutModel.addDrop(a[0], a[1]) },
            "addCluster": { a in WorkoutModel.addCluster(a[0], a[1]) },
            "removeDropAt": { a in try WorkoutModel.removeDropAt(a[0], a.index(1)) },
            "removeClusterAt": { a in try WorkoutModel.removeClusterAt(a[0], a.index(1)) },
            "setDropAt": { a in try WorkoutModel.setDropAt(a[0], a.index(1), a[2]) },
            "setClusterAt": { a in try WorkoutModel.setClusterAt(a[0], a.index(1), a[2]) },
            "nextDropWeight": { a in .number(WorkoutModel.nextDropWeight(a.number(0), pct: a.number(1), grid: a.grid(2))) },
            "nextBurstReps": { a in .number(WorkoutModel.nextBurstReps(a.number(0))) },
            "splitBurstReps": { a in .array(WorkoutModel.splitBurstReps(a.number(0)).map { .number($0) }) },
            "isSideSet": { a in .bool(WorkoutModel.isSideSet(a[0])) },
            "hasCompletedWork": { a in .bool(WorkoutModel.hasCompletedWork(a[0])) },
            "completedVolumeOf": { a in .number(WorkoutModel.completedVolumeOf(a[0])) },
            "makeSideSet": { a in WorkoutModel.makeSideSet(a[0]) },
            "syncSideAggregate": { a in WorkoutModel.syncSideAggregate(a[0]) },
            "setSideField": { a in WorkoutModel.setSideField(a[0], a.side(1), try a.string(2), a[3]) },
            "toggleSide": { a in WorkoutModel.toggleSide(a[0], a.side(1)) },
            "addSideDrop": { a in try WorkoutModel.addSideDrop(a[0], pct: a.number(1), grid: a.grid(2)) },
            "removeSideDropAt": { a in WorkoutModel.removeSideDropAt(a[0], try a.index(1)) },
            "setSideDropAt": { a in WorkoutModel.setSideDropAt(a[0], a.side(1), try a.index(2), a[3]) },
            "addSideCluster": { a in try WorkoutModel.addSideCluster(a[0], restSec: a.number(1)) },
            "removeSideClusterAt": { a in WorkoutModel.removeSideClusterAt(a[0], try a.index(1)) },
            "setSideClusterAt": { a in WorkoutModel.setSideClusterAt(a[0], a.side(1), try a.index(2), a[3]) },
            "normalizeMode": { a in .string(WorkoutModel.normalizeMode(a[0], fallback: a.mode(1)).rawValue) },
            "modeForSet": { a in .string(WorkoutModel.modeForSet(a[0], target: a[1]).rawValue) },
            "modeForEntry": { a in
                let fallback = a[1] == nil || a[1] == .null ? nil : WorkoutModel.normalizeMode(a[1])
                return WorkoutModel.modeForEntry(a[0], fallback: fallback).map { .string($0.rawValue) } ?? .null
            },
        ],
    ]
}

enum FixtureValue {
    static func tag(_ value: JSONValue) -> String? {
        guard case .object(let o) = value, o.count >= 1, case .string(let tag) = o["$js"] else { return nil }
        return tag
    }

    static func decodeArgOrResult(_ value: JSONValue) throws -> JSONValue? {
        tag(value) == "undefined" ? nil : try decode(value)
    }

    static func decode(_ value: JSONValue) throws -> JSONValue {
        switch tag(value) {
        case "NaN": return .number(.nan)
        case "Infinity": return .number(.infinity)
        case "-Infinity": return .number(-.infinity)
        case "-0": return .number(-0.0)
        case "undefined": throw NotDrivable(description: "an undefined nested in an argument has no JSONValue form")
        case let tag?: throw NotDrivable(description: "a nested {\"$js\":\"\(tag)\"} value")
        case nil: break
        }
        switch value {
        case .array(let items): return .array(try items.map(decode))
        case .object(let o): return .object(JSONObject(try o.ordered.map { ($0.key, try decode($0.value)) }))
        default: return value
        }
    }

    static func encode(_ value: JSONValue?) -> JSONValue {
        let tagged = { (tag: String) in JSONValue.object(JSONObject([("$js", .string(tag))])) }
        switch value {
        case nil: return tagged("undefined")
        case .number(let n) where n.isNaN: return tagged("NaN")
        case .number(let n) where n.isInfinite: return tagged(n < 0 ? "-Infinity" : "Infinity")
        case .number(let n) where n == 0 && n.sign == .minus: return tagged("-0")
        case .array(let items): return .array(items.map { encode($0) })
        case .object(let o): return .object(JSONObject(o.ordered.map { ($0.key, encode($0.value)) }))
        case let value?: return value
        }
    }

    static func text(_ value: JSONValue?) -> String {
        JSONSerializer.string(encode(value))
    }

    static func args(_ value: JSONValue) throws -> Args {
        guard case .array(let items) = value else { throw NotDrivable(description: "args is not an array") }
        var values: [JSONValue?] = []
        var replays: [Int: Replay] = [:]
        for (i, item) in items.enumerated() {
            if tag(item) == "function" {
                guard case .array(let calls)? = item.objectValue?["calls"] else { throw NotDrivable(description: "a function argument without calls") }
                replays[i] = Replay(try calls.map { call in
                    guard let args = call.objectValue?["args"], let result = call.objectValue?["result"] else {
                        throw NotDrivable(description: "a callback call that threw")
                    }
                    return (JSONSerializer.serialize(args), result)
                })
                values.append(nil)
            } else {
                values.append(try decodeArgOrResult(item))
            }
        }
        return Args(values: values, replays: replays)
    }
}
