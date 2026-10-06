/// The ECMAScript coercions the lib ports lean on, so each port reads like the JS it mirrors.
/// `nil` stands for `undefined`.
public enum JS {
    public static func isTruthy(_ value: JSONValue?) -> Bool {
        switch value {
        case nil, .null: false
        case .bool(let b): b
        case .number(let n): !(n == 0 || n.isNaN)
        case .string(let s): !s.isEmpty
        case .utf16String(let units): !units.isEmpty
        case .array, .object: true
        }
    }

    /// `Number(value)`.
    public static func toNumber(_ value: JSONValue?) -> Double {
        switch value {
        case nil: .nan
        case .null: 0
        case .bool(let b): b ? 1 : 0
        case .number(let n): n
        case .string(let s): stringToNumber(s)
        case .utf16String, .object: .nan
        case .array: stringToNumber(toString(value))
        }
    }

    /// `String(value)`.
    public static func toString(_ value: JSONValue?) -> String {
        switch value {
        case nil: "undefined"
        case .null: "null"
        case .bool(let b): b ? "true" : "false"
        case .number(let n): numberToString(n)
        case .string(let s): s
        case .utf16String(let units): String(decoding: units, as: UTF16.self)
        case .object: "[object Object]"
        case .array(let items):
            items.map { item in
                switch item {
                case .null: ""
                default: toString(item)
                }
            }.joined(separator: ",")
        }
    }

    public static func numberToString(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n.isInfinite { return n < 0 ? "-Infinity" : "Infinity" }
        return JSONSerializer.string(.number(n))
    }

    /// `Math.round`: halves round toward +Infinity, and the sign of zero survives.
    public static func round(_ x: Double) -> Double {
        guard x.isFinite, x != 0 else { return x }
        if x < 0, x >= -0.5 { return -0.0 }
        let floor = x.rounded(.down)
        return x - floor >= 0.5 ? floor + 1 : floor
    }

    public static func max(_ values: Double...) -> Double { max(values) }
    public static func min(_ values: Double...) -> Double { min(values) }

    /// `Number(value) || fallback`.
    public static func number(_ value: JSONValue?, or fallback: Double = 0) -> Double {
        orFallback(toNumber(value), fallback)
    }

    /// `n || fallback` for a number: NaN and both zeros are falsy.
    public static func orFallback(_ n: Double, _ fallback: Double = 0) -> Double {
        n.isNaN || n == 0 ? fallback : n
    }

    /// `Math.max`: NaN wins, and +0 beats -0.
    public static func max(_ values: [Double]) -> Double {
        var result = -Double.infinity
        for v in values {
            if v.isNaN { return .nan }
            if v > result || (v == 0 && result == 0 && result.sign == .minus) { result = v }
        }
        return result
    }

    /// `Math.min`: NaN wins, and -0 beats +0.
    public static func min(_ values: [Double]) -> Double {
        var result = Double.infinity
        for v in values {
            if v.isNaN { return .nan }
            if v < result || (v == 0 && result == 0 && v.sign == .minus) { result = v }
        }
        return result
    }

    /// `value?.[key]` for the plain data a state holds: only an object has named properties.
    public static func member(_ value: JSONValue?, _ key: String) -> JSONValue? {
        value?.objectValue?[key]
    }

    /// The own enumerable properties `{...value}` copies.
    public static func spread(_ value: JSONValue?) -> JSONObject {
        switch value {
        case .object(let o): return o
        case .array(let items):
            return JSONObject(items.enumerated().map { (String($0.offset), $0.element) })
        case .string(let s):
            return JSONObject(Array(s.utf16).enumerated().map { (String($0.offset), utf16Value([$0.element])) })
        case .utf16String(let units):
            return JSONObject(units.enumerated().map { (String($0.offset), utf16Value([$0.element])) })
        default:
            return JSONObject()
        }
    }

    /// `typeof value === 'string' ? value.trim().toLowerCase() : ''`.
    public static func token(_ value: JSONValue?) -> JSONKey {
        guard case .string(let s) = value else { return "" }
        return JSONKey(trimmedLowercase(s))
    }

    /// `s.trim().toLowerCase()`.
    public static func trimmedLowercase(_ s: String) -> String {
        let scalars = s.unicodeScalars
        guard let start = scalars.firstIndex(where: { !isWhitespace($0) }),
              let end = scalars.lastIndex(where: { !isWhitespace($0) }) else { return "" }
        return String(scalars[start...end]).lowercased()
    }

    static func utf16Value(_ units: [UInt16]) -> JSONValue {
        if let s = String(validating: units, as: UTF16.self) { return .string(s) }
        return .utf16String(units)
    }

    /// ECMAScript WhiteSpace and LineTerminator.
    static func isWhitespace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x2028, 0x2029, 0xFEFF: true
        default: c.properties.generalCategory == .spaceSeparator
        }
    }

    /// StringToNumber: surrounding whitespace ignored, empty is 0, else a decimal, `Infinity`, or
    /// an unsigned 0x/0o/0b literal; anything else is NaN.
    static func stringToNumber(_ s: String) -> Double {
        let scalars = s.unicodeScalars
        guard let start = scalars.firstIndex(where: { !isWhitespace($0) }),
              let end = scalars.lastIndex(where: { !isWhitespace($0) }) else { return 0 }
        let text = String(scalars[start...end])
        let bytes = Array(text.utf8)
        if bytes.count > 2, bytes[0] == UInt8(ascii: "0") {
            let radix: Int? = switch bytes[1] {
            case UInt8(ascii: "x"), UInt8(ascii: "X"): 16
            case UInt8(ascii: "o"), UInt8(ascii: "O"): 8
            case UInt8(ascii: "b"), UInt8(ascii: "B"): 2
            default: nil
            }
            if let radix {
                var n = 0.0
                for b in bytes[2...] {
                    guard let d = Int(String(UnicodeScalar(b)), radix: radix) else { return .nan }
                    n = n * Double(radix) + Double(d)
                }
                return n
            }
        }
        var body = bytes[...]
        var negative = false
        if let sign = body.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
            negative = sign == UInt8(ascii: "-")
            body = body.dropFirst()
        }
        if body.elementsEqual("Infinity".utf8) { return negative ? -.infinity : .infinity }
        guard isDecimalLiteral(body), let n = Double(text) else { return .nan }
        return n
    }

    static func isDecimalLiteral(_ bytes: ArraySlice<UInt8>) -> Bool {
        var i = bytes.startIndex
        let isDigit = { (b: UInt8) in b >= 0x30 && b <= 0x39 }
        var intDigits = 0
        while i < bytes.endIndex, isDigit(bytes[i]) { i += 1; intDigits += 1 }
        var fracDigits = 0
        if i < bytes.endIndex, bytes[i] == UInt8(ascii: ".") {
            i += 1
            while i < bytes.endIndex, isDigit(bytes[i]) { i += 1; fracDigits += 1 }
        }
        guard intDigits + fracDigits > 0 else { return false }
        if i < bytes.endIndex, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            i += 1
            if i < bytes.endIndex, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            var expDigits = 0
            while i < bytes.endIndex, isDigit(bytes[i]) { i += 1; expDigits += 1 }
            guard expDigits > 0 else { return false }
        }
        return i == bytes.endIndex
    }
}

/// A `TypeError` the JS original throws, with V8's message.
public struct JSTypeError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
