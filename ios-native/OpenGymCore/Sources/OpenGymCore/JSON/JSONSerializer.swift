/// Writes a `JSONValue` exactly as `JSON.stringify(value)` would, as UTF-8 bytes.
public enum JSONSerializer {
    public static func serialize(_ value: JSONValue) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(256)
        write(value, into: &out)
        return out
    }

    public static func string(_ value: JSONValue) -> String {
        String(decoding: serialize(value), as: UTF8.self)
    }

    static func write(_ value: JSONValue, into out: inout [UInt8]) {
        switch value {
        case .null:
            out.append(contentsOf: "null".utf8)
        case .bool(let b):
            out.append(contentsOf: (b ? "true" : "false").utf8)
        case .number(let n):
            writeNumber(n, into: &out)
        case .string(let s):
            writeString(s, into: &out)
        case .utf16String(let units):
            writeUTF16String(units, into: &out)
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for (i, item) in items.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                write(item, into: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let object):
            out.append(UInt8(ascii: "{"))
            for (i, entry) in object.ordered.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                writeString(entry.key, into: &out)
                out.append(UInt8(ascii: ":"))
                write(entry.value, into: &out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    static func writeString(_ s: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        var s = s
        s.withUTF8 { bytes in
            var runStart = 0
            for i in 0..<bytes.count {
                let byte = bytes[i]
                if byte >= 0x20, byte != 0x22, byte != 0x5C { continue }
                out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<i]))
                writeByte(byte, into: &out)
                runStart = i + 1
            }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart...]))
        }
        out.append(UInt8(ascii: "\""))
    }

    static func writeUTF16String(_ units: [UInt16], into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        var i = 0
        while i < units.count {
            let unit = UInt32(units[i])
            i += 1
            if (0xD800...0xDBFF).contains(unit), i < units.count, (0xDC00...0xDFFF).contains(UInt32(units[i])) {
                let scalar = 0x10000 + ((unit - 0xD800) << 10) + (UInt32(units[i]) - 0xDC00)
                i += 1
                out.append(UInt8(0xF0 | scalar >> 18))
                out.append(UInt8(0x80 | scalar >> 12 & 0x3F))
                out.append(UInt8(0x80 | scalar >> 6 & 0x3F))
                out.append(UInt8(0x80 | scalar & 0x3F))
            } else if (0xD800...0xDFFF).contains(unit) {
                writeUnicodeEscape(unit, into: &out)
            } else if unit < 0x80 {
                writeByte(UInt8(unit), into: &out)
            } else if unit < 0x800 {
                out.append(UInt8(0xC0 | unit >> 6))
                out.append(UInt8(0x80 | unit & 0x3F))
            } else {
                out.append(UInt8(0xE0 | unit >> 12))
                out.append(UInt8(0x80 | unit >> 6 & 0x3F))
                out.append(UInt8(0x80 | unit & 0x3F))
            }
        }
        out.append(UInt8(ascii: "\""))
    }

    static func writeByte(_ byte: UInt8, into out: inout [UInt8]) {
        switch byte {
        case 0x22: out.append(contentsOf: [0x5C, 0x22])
        case 0x5C: out.append(contentsOf: [0x5C, 0x5C])
        case 0x08: out.append(contentsOf: [0x5C, UInt8(ascii: "b")])
        case 0x0C: out.append(contentsOf: [0x5C, UInt8(ascii: "f")])
        case 0x0A: out.append(contentsOf: [0x5C, UInt8(ascii: "n")])
        case 0x0D: out.append(contentsOf: [0x5C, UInt8(ascii: "r")])
        case 0x09: out.append(contentsOf: [0x5C, UInt8(ascii: "t")])
        case 0x00..<0x20: writeUnicodeEscape(UInt32(byte), into: &out)
        default: out.append(byte)
        }
    }

    static func writeUnicodeEscape(_ unit: UInt32, into out: inout [UInt8]) {
        let digits = Array("0123456789abcdef".utf8)
        out.append(contentsOf: [0x5C, UInt8(ascii: "u")])
        out.append(digits[Int(unit >> 12 & 0xF)])
        out.append(digits[Int(unit >> 8 & 0xF)])
        out.append(digits[Int(unit >> 4 & 0xF)])
        out.append(digits[Int(unit & 0xF)])
    }

    /// ECMAScript Number::toString. Non-finite values are `null`, as in `JSON.stringify`.
    static func writeNumber(_ value: Double, into out: inout [UInt8]) {
        guard value.isFinite else {
            out.append(contentsOf: "null".utf8)
            return
        }
        if value == 0 {
            out.append(UInt8(ascii: "0"))
            return
        }
        var magnitude = value
        if value < 0 {
            out.append(UInt8(ascii: "-"))
            magnitude = -value
        }
        if magnitude < 9_007_199_254_740_992, magnitude == magnitude.rounded(.towardZero) {
            writeInteger(UInt64(magnitude), into: &out)
            return
        }
        let (digits, pointPosition) = shortestDigits(magnitude)
        let k = digits.count
        let n = pointPosition
        if k <= n, n <= 21 {
            out.append(contentsOf: digits)
            out.append(contentsOf: repeatElement(UInt8(ascii: "0"), count: n - k))
        } else if 0 < n, n <= 21 {
            out.append(contentsOf: digits[0..<n])
            out.append(UInt8(ascii: "."))
            out.append(contentsOf: digits[n...])
        } else if -6 < n, n <= 0 {
            out.append(contentsOf: "0.".utf8)
            out.append(contentsOf: repeatElement(UInt8(ascii: "0"), count: -n))
            out.append(contentsOf: digits)
        } else {
            out.append(digits[0])
            if k > 1 {
                out.append(UInt8(ascii: "."))
                out.append(contentsOf: digits[1...])
            }
            out.append(UInt8(ascii: "e"))
            let exponent = n - 1
            out.append(exponent < 0 ? UInt8(ascii: "-") : UInt8(ascii: "+"))
            writeInteger(UInt64(abs(exponent)), into: &out)
        }
    }

    static func writeInteger(_ value: UInt64, into out: inout [UInt8]) {
        if value == 0 {
            out.append(UInt8(ascii: "0"))
            return
        }
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 20) { digits in
            var end = 20
            var v = value
            while v > 0 {
                end -= 1
                digits[end] = UInt8(ascii: "0") + UInt8(v % 10)
                v /= 10
            }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: digits[end...]))
        }
    }

    /// The shortest round-trip decimal digits of a positive finite double, without leading or
    /// trailing zeros, and the position of the decimal point relative to the first digit:
    /// value = 0.d1d2…dk × 10^pointPosition.
    ///
    /// Swift's `description` already picks the shortest round-trip digits; this only re-reads
    /// them out of Swift's own layout.
    static func shortestDigits(_ value: Double) -> (digits: [UInt8], pointPosition: Int) {
        var digits: [UInt8] = []
        var integerDigits = 0
        var exponent = 0
        var seenPoint = false
        var seenExponent = false
        var exponentNegative = false
        for byte in value.description.utf8 {
            switch byte {
            case UInt8(ascii: "."): seenPoint = true
            case UInt8(ascii: "e"), UInt8(ascii: "E"): seenExponent = true
            case UInt8(ascii: "-"): exponentNegative = true
            case UInt8(ascii: "+"): break
            default:
                if seenExponent {
                    exponent = exponent * 10 + Int(byte - 0x30)
                } else {
                    digits.append(byte)
                    if !seenPoint { integerDigits += 1 }
                }
            }
        }
        if exponentNegative { exponent = -exponent }
        var pointPosition = integerDigits + exponent
        var leading = 0
        while leading < digits.count, digits[leading] == UInt8(ascii: "0") {
            leading += 1
            pointPosition -= 1
        }
        var trailing = digits.count
        while trailing > leading, digits[trailing - 1] == UInt8(ascii: "0") { trailing -= 1 }
        return (Array(digits[leading..<trailing]), pointPosition)
    }
}
