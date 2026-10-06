/// The two bounds double progression works between, ported from `frontend/src/lib/rep-range.js`.
/// `reps` is the upper bound and `repsMin` the lower, as persisted configs store them.
public struct RepRange: Equatable, Sendable {
    public let reps: Double
    public let repsMin: Double

    /// `normalizeRepRange(reps, repsMin, stride)`. A stride that is not a positive integer is 1.
    public static func normalize(reps: JSONValue?, repsMin: JSONValue?, stride: JSONValue? = nil) -> RepRange {
        let step: Double = if case .number(let n) = stride, n > 0, n == n.rounded(.towardZero), n.isFinite { n } else { 1 }
        let upper = align(positiveInt(reps, fallback: 10), step)
        let lower = align(positiveInt(repsMin, fallback: JS.max(1, upper - 2)), step)
        return lower >= upper
            ? RepRange(reps: lower + step, repsMin: lower)
            : RepRange(reps: upper, repsMin: lower)
    }

    public var json: JSONValue {
        .object(JSONObject([("reps", .number(reps)), ("repsMin", .number(repsMin))]))
    }

    private static func align(_ value: Double, _ stride: Double) -> Double {
        JS.max(stride, (value / stride).rounded(.up) * stride)
    }

    private static func positiveInt(_ value: JSONValue?, fallback: Double) -> Double {
        let n = JS.toNumber(value)
        return n.isFinite && n > 0 ? JS.max(1, JS.round(n)) : fallback
    }
}
