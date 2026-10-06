/// Set-row semantics shared by session, history and strength views, ported from
/// `frontend/src/lib/workout-model.js`. Rows stay `JSONValue` so every key the web app wrote
/// survives an edit in its original position; `nil` stands for `undefined`.
public enum SetPhase: String, Sendable {
    case warmup, work
}

public enum SetType: String, Sendable {
    case straight, dropset, restpause
}

public enum SetMode: String, Sendable, CaseIterable {
    case reps, time, cardio
}

public enum Side: String, Sendable {
    case L, R
}

/// What a drop's weight snaps to: the nearest 0.5, a positive weight step, or a function that
/// snaps onto the plates you own.
public enum DropGrid {
    case halfStep
    case step(Double)
    case snap((Double) -> Double)
}

public enum WorkoutModel {
    public static let weightOriginManual = "manual"

    static func objectOf(_ value: JSONValue?) -> JSONObject {
        value?.objectValue ?? JSONObject()
    }

    static func isNullish(_ value: JSONValue?) -> Bool {
        value == nil || value == .null
    }

    // MARK: Phase and set type

    static func normalizedPhase(_ value: JSONValue?, fallback: SetPhase) -> SetPhase {
        switch JS.token(value) {
        case "warmup", "warm-up", "warm_up": .warmup
        case "work": .work
        default: fallback
        }
    }

    /// An explicit phase wins over the legacy `warmup` boolean.
    public static func phaseForSet(_ set: JSONValue?, fallback: SetPhase = .work) -> SetPhase {
        let source = objectOf(set)
        if !isNullish(source["phase"]), source["phase"] != .string("") {
            return normalizedPhase(source["phase"], fallback: fallback)
        }
        return source["warmup"] == .bool(true) ? .warmup : fallback
    }

    public static func isWarmupRow(_ set: JSONValue?) -> Bool {
        phaseForSet(set) == .warmup
    }

    public static func setType(_ set: JSONValue?) -> SetType {
        switch objectOf(set)["type"] {
        case .string("dropset"): .dropset
        case .string("restpause"): .restpause
        default: .straight
        }
    }

    public static func isDropSet(_ set: JSONValue?) -> Bool { setType(set) == .dropset }
    public static func isRestPauseSet(_ set: JSONValue?) -> Bool { setType(set) == .restpause }

    public static func dropsOf(_ set: JSONValue?) -> [JSONValue] {
        let source = objectOf(set)
        guard isDropSet(.object(source)), case .array(let drops) = source["drops"] else { return [] }
        return drops
    }

    public static func clustersOf(_ set: JSONValue?) -> [JSONValue] {
        let source = objectOf(set)
        guard isRestPauseSet(.object(source)), case .array(let clusters) = source["clusters"] else { return [] }
        return clusters
    }

    // MARK: Volume

    static func dropVolume(_ drops: [JSONValue]) -> Double {
        drops.reduce(0) { v, d in v + JS.number(JS.member(d, "w")) * JS.number(JS.member(d, "r")) }
    }

    /// Weight x reps of a drop-set's drops on top of its main set. A rest-pause row's own `r`
    /// already counts every burst, so clusters add nothing here.
    public static func extraVolumeOf(_ set: JSONValue?) -> Double {
        let source = objectOf(set)
        if isSideSet(.object(source)) {
            let sides = JS.member(.object(source), "sides")
            return [JS.member(sides, "L"), JS.member(sides, "R")].reduce(0) { v, side in v + dropVolume(dropsOf(side)) }
        }
        return dropVolume(dropsOf(.object(source)))
    }

    public static func hasCompletedWork(_ set: JSONValue?) -> Bool {
        guard isSideSet(set) else { return JS.member(set, "done") == .bool(true) }
        let sides = JS.member(set, "sides")
        return JS.member(JS.member(sides, "L"), "done") == .bool(true) || JS.member(JS.member(sides, "R"), "done") == .bool(true)
    }

    public static func completedVolumeOf(_ set: JSONValue?) -> Double {
        if isSideSet(set) {
            let sides = JS.member(set, "sides")
            return completedVolumeOf(JS.member(sides, "L")) + completedVolumeOf(JS.member(sides, "R"))
        }
        guard JS.isTruthy(JS.member(set, "done")) else { return 0 }
        return JS.number(JS.member(set, "w")) * JS.number(JS.member(set, "r")) + extraVolumeOf(set)
    }

    // MARK: Drops and clusters

    public static func addDrop(_ set: JSONValue?, _ drop: JSONValue?) -> JSONValue {
        var out = objectOf(set)
        let prev = out["drops"]?.arrayValue ?? []
        out["type"] = .string("dropset")
        out["drops"] = .array(prev + [.object(JSONObject([
            ("w", .number(JS.number(JS.member(drop, "w")))),
            ("r", .number(JS.number(JS.member(drop, "r")))),
        ]))])
        return .object(out)
    }

    public static func addCluster(_ set: JSONValue?, _ cluster: JSONValue?) -> JSONValue {
        var out = objectOf(set)
        let prev = out["clusters"]?.arrayValue ?? []
        out["type"] = .string("restpause")
        out["clusters"] = .array(prev + [.object(JSONObject([
            ("r", .number(JS.number(JS.member(cluster, "r")))),
            ("restSec", .number(JS.number(JS.member(cluster, "restSec")))),
        ]))])
        return .object(out)
    }

    public static func removeDropAt(_ set: JSONValue?, _ i: Int) throws(JSTypeError) -> JSONValue {
        let source = objectOf(set)
        return removing(i, key: "drops", items: try list(source, "drops", calling: "filter"), from: source)
    }

    public static func removeClusterAt(_ set: JSONValue?, _ i: Int) throws(JSTypeError) -> JSONValue {
        let source = objectOf(set)
        return removing(i, key: "clusters", items: try list(source, "clusters", calling: "filter"), from: source)
    }

    public static func setDropAt(_ set: JSONValue?, _ i: Int, _ patch: JSONValue?) throws(JSTypeError) -> JSONValue? {
        try patching(set, key: "drops", at: i) { for (k, v) in JS.spread(patch).ordered { $0[k] = v } }
    }

    public static func setClusterAt(_ set: JSONValue?, _ i: Int, _ patch: JSONValue?) throws(JSTypeError) -> JSONValue? {
        try patching(set, key: "clusters", at: i) { for (k, v) in JS.spread(patch).ordered { $0[k] = v } }
    }

    /// `(objectOf(set)[key] || [])` as the array the JS then calls `method` on.
    static func list(_ source: JSONObject, _ key: String, calling method: String) throws(JSTypeError) -> [JSONValue] {
        let value = source[key]
        guard JS.isTruthy(value) else { return [] }
        guard case .array(let items) = value else {
            throw JSTypeError("(objectOf(...).\(key) || []).\(method) is not a function")
        }
        return items
    }

    /// Clearing the last item reverts the row to a straight set.
    static func removing(_ i: Int, key: String, items: [JSONValue], from source: JSONObject) -> JSONValue {
        let kept = items.enumerated().filter { $0.offset != i }.map(\.element)
        var out = source
        if kept.isEmpty { out["type"] = .string("straight") }
        out[key] = .array(kept)
        return .object(out)
    }

    /// `items.slice()`, then `{...items[i], ...patch}` in place; the row comes back untouched when
    /// there is no item at `i`.
    static func patching(_ set: JSONValue?, key: String, at i: Int, _ patch: (inout JSONObject) -> Void) throws(JSTypeError) -> JSONValue? {
        let source = objectOf(set)
        let items: [JSONValue]
        switch source[key] {
        case let value where !JS.isTruthy(value):
            items = []
        case .array(let array):
            items = array
        case .string(let s):
            if i >= 0, i < s.utf16.count { throw JSTypeError("Cannot assign to read only property '\(i)' of string '\(s)'") }
            return set
        case .utf16String(let units):
            if i >= 0, i < units.count { throw JSTypeError("Cannot assign to read only property '\(i)' of string '\(JS.toString(.utf16String(units)))'") }
            return set
        default:
            throw JSTypeError("(objectOf(...).\(key) || []).slice is not a function")
        }
        return patched(source, key: key, items: items, at: i, patch).map { .object($0) } ?? set
    }

    /// Nil when there is no item at `i`.
    static func patched(_ source: JSONObject, key: String, items: [JSONValue], at i: Int, _ patch: (inout JSONObject) -> Void) -> JSONObject? {
        guard i >= 0, i < items.count, JS.isTruthy(items[i]) else { return nil }
        var items = items
        var item = JS.spread(items[i])
        patch(&item)
        items[i] = .object(item)
        var out = source
        out[key] = .array(items)
        return out
    }

    /// The next drop's weight: `pct`% lighter than the previous one, snapped to `grid`, and never
    /// at or above the weight it drops from.
    public static func nextDropWeight(_ prevWeight: Double, pct: Double = 20, grid: DropGrid = .halfStep) -> Double {
        let p = JS.min(90, JS.max(1, JS.orFallback(pct, 20)))
        let prev = JS.max(0, JS.orFallback(prevWeight))
        let raw = prev * (1 - p / 100)
        let tidy = { (w: Double) in JS.round(w * 1000) / 1000 }
        switch grid {
        case .snap(let snap):
            let w = snap(raw)
            if w.isFinite, w >= 0 { return tidy(w) }
        case .step(let step) where step > 0:
            var w = JS.round(raw / step) * step
            if prev > 0, w >= prev { w = prev - step }
            return tidy(JS.max(0, w))
        case .step, .halfStep:
            break
        }
        return JS.round(raw * 2) / 2
    }

    /// Roughly half the previous burst's reps, at least one.
    public static func nextBurstReps(_ prevReps: Double) -> Double {
        JS.max(1, JS.round(JS.orFallback(prevReps) / 2))
    }

    /// A rest-pause total split into descending, roughly halving bursts that add back up to it.
    public static func splitBurstReps(_ total: Double) -> [Double] {
        var bursts: [Double] = []
        var remaining = JS.max(0, JS.round(JS.orFallback(total)))
        while remaining > 0 {
            let burst = JS.min(remaining, nextBurstReps(remaining))
            bursts.append(burst)
            remaining -= burst
        }
        return bursts
    }

    // MARK: Per-side sets
    //
    // A per-side row logs each limb in `sides: {L, R}` and keeps a scalar summary for readers that
    // predate it: r = L.r + R.r, w = max(L.w, R.w), done = L.done && R.done, and the harder side's
    // effort. `syncSideAggregate` recomputes that summary after every per-side edit.

    public static func isSideSet(_ set: JSONValue?) -> Bool {
        guard case .object(let sides) = objectOf(set)["sides"] else { return false }
        return JS.isTruthy(sides["L"]) && JS.isTruthy(sides["R"])
    }

    static func sideOf(_ value: JSONValue?) -> JSONObject {
        let v = objectOf(value)
        var out = JSONObject([
            ("w", .number(JS.number(v["w"]))),
            ("r", .number(JS.number(v["r"]))),
            ("done", .bool(v["done"] == .bool(true))),
        ])
        if !isNullish(v["rir"]) { out["rir"] = v["rir"] }
        if !isNullish(v["rpe"]) { out["rpe"] = v["rpe"] }
        if v["weightOrigin"] == .string(weightOriginManual) { out["weightOrigin"] = .string(weightOriginManual) }
        if v["type"] == .string("dropset") || v["type"] == .string("restpause") { out["type"] = v["type"] }
        if case .array = v["drops"] { out["drops"] = v["drops"] }
        if case .array = v["clusters"] { out["clusters"] = v["clusters"] }
        return out
    }

    /// A per-side row from a plain one: each side gets half the reps at the same weight.
    public static func makeSideSet(_ row: JSONValue? = nil) -> JSONValue {
        var next = objectOf(row)
        let half = JS.round(JS.number(next["r"]) / 2)
        let side = JSONValue.object(JSONObject([("w", .number(JS.number(next["w"]))), ("r", .number(half)), ("done", .bool(false))]))
        next["sides"] = .object(JSONObject([("L", side), ("R", side)]))
        next.remove("rir")
        next.remove("rpe")
        return syncSideAggregate(.object(next))
    }

    public static func syncSideAggregate(_ row: JSONValue?) -> JSONValue {
        let base = objectOf(row)
        guard isSideSet(.object(base)), let sides = base["sides"]?.objectValue else { return .object(base) }
        let left = sideOf(sides["L"])
        let right = sideOf(sides["R"])
        let num = { (side: JSONObject, key: String) in side[key]?.numberValue ?? 0 }
        var out = base
        out["sides"] = .object(JSONObject([("L", .object(left)), ("R", .object(right))]))
        out["r"] = .number(num(left, "r") + num(right, "r"))
        out["w"] = .number(JS.max(num(left, "w"), num(right, "w")))
        out["done"] = .bool(left["done"] == .bool(true) && right["done"] == .bool(true))
        out.remove("rir")
        out.remove("rpe")
        let rirs = [left["rir"], right["rir"]].compactMap { $0 }
        let rpes = [left["rpe"], right["rpe"]].compactMap { $0 }
        if !rirs.isEmpty {
            out["rir"] = .number(JS.min(rirs.map { JS.toNumber($0) }))
        } else if !rpes.isEmpty {
            out["rpe"] = .number(JS.max(rpes.map { JS.toNumber($0) }))
        }
        out.remove("drops")
        out.remove("clusters")
        out.remove("type")
        let leftType = setType(.object(left))
        let sideType = leftType != .straight ? leftType : setType(.object(right))
        if sideType != .straight { out["type"] = .string(sideType.rawValue) }
        return .object(out)
    }

    /// A nil `value` clears an optional field (effort), as a straight row drops the key.
    public static func setSideField(_ row: JSONValue?, _ side: Side?, _ field: String, _ value: JSONValue?) -> JSONValue {
        patchSide(row, side) { cur in
            var cur = cur
            if isNullish(value), field == "rir" || field == "rpe" {
                cur.remove(field)
            } else {
                cur[field] = value
            }
            return .object(cur)
        }
    }

    public static func toggleSide(_ row: JSONValue?, _ side: Side?) -> JSONValue {
        patchSide(row, side) { cur in
            var cur = cur
            cur["done"] = .bool(cur["done"] != .bool(true))
            return .object(cur)
        }
    }

    static func patchSide(_ row: JSONValue?, _ side: Side?, _ edit: (JSONObject) -> JSONValue?) -> JSONValue {
        let base = objectOf(row)
        guard isSideSet(.object(base)), let side, var sides = base["sides"]?.objectValue else { return .object(base) }
        sides[side.rawValue] = edit(sideOf(sides[side.rawValue]))
        var next = base
        next["sides"] = .object(sides)
        return syncSideAggregate(.object(next))
    }

    static func patchBothSides<E: Error>(_ row: JSONValue?, _ edit: (JSONObject) throws(E) -> JSONValue) throws(E) -> JSONValue {
        let base = objectOf(row)
        guard isSideSet(.object(base)), let sides = base["sides"]?.objectValue else { return .object(base) }
        var next = base
        next["sides"] = .object(JSONObject([("L", try edit(sideOf(sides["L"]))), ("R", try edit(sideOf(sides["R"])))]))
        return syncSideAggregate(.object(next))
    }

    /// `items[items.length - 1][key]`, which throws on a null last item as JS does.
    static func lastItem(_ items: [JSONValue], _ key: String) throws(JSTypeError) -> JSONValue? {
        if items.last == .null { throw JSTypeError("Cannot read properties of null (reading '\(key)')") }
        return JS.member(items.last, key)
    }

    /// Appends a drop to both sides, each seeded from its own side's weight and reps.
    public static func addSideDrop(_ row: JSONValue?, pct: Double = 20, grid: DropGrid = .halfStep) throws(JSTypeError) -> JSONValue {
        try patchBothSides(row) { side throws(JSTypeError) in
            let drops = dropsOf(.object(side))
            let base = drops.isEmpty ? JS.number(side["w"]) : JS.number(try lastItem(drops, "w"))
            return addDrop(.object(side), .object(JSONObject([
                ("w", .number(nextDropWeight(base, pct: pct, grid: grid))),
                ("r", side["r"] ?? .null),
            ])))
        }
    }

    public static func removeSideDropAt(_ row: JSONValue?, _ i: Int) -> JSONValue {
        patchBothSides(row) { side in
            removing(i, key: "drops", items: side["drops"]?.arrayValue ?? [], from: side)
        }
    }

    public static func setSideDropAt(_ row: JSONValue?, _ side: Side?, _ i: Int, _ patch: JSONValue?) -> JSONValue {
        patchSide(row, side) { sd in
            .object(patched(sd, key: "drops", items: sd["drops"]?.arrayValue ?? [], at: i) { for (k, v) in JS.spread(patch).ordered { $0[k] = v } } ?? sd)
        }
    }

    /// Appends a burst to both sides; a rest-pause side's own `r` is the running total.
    public static func addSideCluster(_ row: JSONValue?, restSec: Double) throws(JSTypeError) -> JSONValue {
        try patchBothSides(row) { side throws(JSTypeError) in
            let clusters = clustersOf(.object(side))
            let r = JS.number(side["r"])
            let base = clusters.isEmpty ? r : JS.toNumber(try lastItem(clusters, "r"))
            let added = nextBurstReps(base)
            var out = JS.spread(addCluster(.object(side), .object(JSONObject([("r", .number(added)), ("restSec", .number(restSec))]))))
            out["r"] = .number(r + added)
            return .object(out)
        }
    }

    public static func removeSideClusterAt(_ row: JSONValue?, _ i: Int) -> JSONValue {
        patchBothSides(row) { side in
            let clusters = clustersOf(.object(side))
            let removed = i >= 0 && i < clusters.count ? JS.member(clusters[i], "r") : nil
            var out = JS.spread(removing(i, key: "clusters", items: side["clusters"]?.arrayValue ?? [], from: side))
            let r = JS.number(side["r"]) - (JS.isTruthy(removed) ? JS.toNumber(removed) : 0)
            out["r"] = .number(JS.max(0, r))
            return .object(out)
        }
    }

    public static func setSideClusterAt(_ row: JSONValue?, _ side: Side?, _ i: Int, _ r: JSONValue?) -> JSONValue {
        patchSide(row, side) { sd in
            let clusters = clustersOf(.object(sd))
            let current = i >= 0 && i < clusters.count ? JS.member(clusters[i], "r") : nil
            let delta = JS.number(r) - (JS.isTruthy(current) ? JS.toNumber(current) : 0)
            var out = patched(sd, key: "clusters", items: sd["clusters"]?.arrayValue ?? [], at: i) { $0["r"] = r } ?? sd
            out["r"] = .number(JS.max(0, JS.number(sd["r"]) + delta))
            return .object(out)
        }
    }

    // MARK: Modes

    public static func normalizeMode(_ value: JSONValue?, fallback: SetMode = .reps) -> SetMode {
        SetMode(rawValue: JS.token(value)) ?? fallback
    }

    static func modeFromUnit(_ value: JSONValue?) -> SetMode? {
        switch JS.token(value) {
        case "rep", "reps", "repetition", "repetitions": .reps
        case "sec", "secs", "second", "seconds": .time
        case "min", "mins", "minute", "minutes": .cardio
        default: nil
        }
    }

    static func explicitMode(_ source: JSONValue?) -> SetMode? {
        let value = objectOf(source)
        return SetMode(rawValue: JS.token(value["mode"])) ?? modeFromUnit(value["unit"])
    }

    static func inferredMode(_ source: JSONValue?) -> SetMode? {
        let value = objectOf(source)
        if let explicit = explicitMode(.object(value)) { return explicit }
        let mode = value["mode"]
        if JS.trimmedLowercase(JS.isTruthy(mode) ? JS.toString(mode) : "") == "amrap" { return .reps }
        let has = { (key: String) in !isNullish(value[key]) }
        if has("min") || has("speed") { return .cardio }
        if has("sec") || has("seconds") || has("durationSec") { return .time }
        if has("r") || has("reps") || has("actualReps") { return .reps }
        return nil
    }

    /// The explicit row mode, then the parent target's, then legacy result fields.
    public static func modeForSet(_ set: JSONValue?, target: JSONValue? = nil) -> SetMode {
        explicitMode(set) ?? inferredMode(target) ?? inferredMode(set) ?? .reps
    }

    /// One mode for an entry, or nil when its work rows mix modes.
    public static func modeForEntry(_ entry: JSONValue?, fallback: SetMode? = nil) -> SetMode? {
        let source = objectOf(entry)
        let target = JSONValue.object(objectOf(JS.isTruthy(source["target"]) ? source["target"] : .object(source)))
        let sets = source["sets"]?.arrayValue ?? []
        let work = sets.filter { !isWarmupRow($0) }
        var modes: [SetMode] = []
        for set in work.isEmpty ? sets : work {
            let mode = modeForSet(set, target: target)
            if !modes.contains(mode) { modes.append(mode) }
        }
        if modes.count > 1 { return nil }
        if let only = modes.first { return only }
        if let targetMode = inferredMode(target) { return targetMode }
        return fallback ?? modeForSet(.object(source), target: target)
    }
}
