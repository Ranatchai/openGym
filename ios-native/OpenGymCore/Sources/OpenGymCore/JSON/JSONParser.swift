public struct JSONParseError: Error, Equatable, CustomStringConvertible {
    public let offset: Int
    public let message: String

    public init(offset: Int, message: String) {
        self.offset = offset
        self.message = message
    }

    public var description: String { "\(message) at byte \(offset)" }
}

/// Strict JSON (RFC 8259) from UTF-8 bytes, with the `JSON.parse` behaviors that matter for
/// byte parity: duplicate keys keep the last value at the first key's position, `-0` stays
/// negative, and a lone surrogate escape yields a `.utf16String`.
public enum JSONParser {
    public static func parse(_ bytes: [UInt8]) throws -> JSONValue {
        try bytes.withUnsafeBufferPointer { buffer in
            var parser = Parser(buffer: buffer)
            parser.skipWhitespace()
            let value = try parser.parseValue(depth: 0)
            parser.skipWhitespace()
            guard parser.position == buffer.count else { throw parser.error("unexpected content after the document") }
            return value
        }
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Array(text.utf8))
    }

    static let maxDepth = 256
}

private struct Parser {
    let buffer: UnsafeBufferPointer<UInt8>
    var position = 0
    var scratch: [UInt8] = []

    init(buffer: UnsafeBufferPointer<UInt8>) {
        self.buffer = buffer
    }

    func error(_ message: String, at offset: Int? = nil) -> JSONParseError {
        JSONParseError(offset: offset ?? position, message: message)
    }

    func unexpected() -> JSONParseError {
        if position >= buffer.count { return error("unexpected end of input") }
        return error("unexpected byte 0x\(hex(buffer[position]))")
    }

    mutating func skipWhitespace() {
        while position < buffer.count {
            let byte = buffer[position]
            guard byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 else { return }
            position += 1
        }
    }

    mutating func parseValue(depth: Int) throws -> JSONValue {
        guard position < buffer.count else { throw unexpected() }
        switch buffer[position] {
        case UInt8(ascii: "{"): return try parseObject(depth: depth + 1)
        case UInt8(ascii: "["): return try parseArray(depth: depth + 1)
        case UInt8(ascii: "\""): return try parseString()
        case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try expectLiteral("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
        default: throw unexpected()
        }
    }

    mutating func expectLiteral(_ literal: StaticString) throws {
        let length = literal.utf8CodeUnitCount
        guard position + length <= buffer.count else { throw error("unexpected end of input", at: buffer.count) }
        let start = position
        let matches = literal.withUTF8Buffer { expected in
            (0..<length).allSatisfy { buffer[start + $0] == expected[$0] }
        }
        guard matches else { throw unexpected() }
        position += length
    }

    mutating func parseObject(depth: Int) throws -> JSONValue {
        guard depth <= JSONParser.maxDepth else { throw error("nesting deeper than \(JSONParser.maxDepth)") }
        position += 1
        var object = JSONObject()
        skipWhitespace()
        if position < buffer.count, buffer[position] == UInt8(ascii: "}") {
            position += 1
            return .object(object)
        }
        while true {
            guard position < buffer.count, buffer[position] == UInt8(ascii: "\"") else { throw unexpected() }
            let keyOffset = position
            let key: String
            switch try parseString() {
            case .string(let s): key = s
            case .utf16String: throw error("unpaired surrogate in object key", at: keyOffset)
            default: throw unexpected()
            }
            skipWhitespace()
            guard position < buffer.count, buffer[position] == UInt8(ascii: ":") else { throw unexpected() }
            position += 1
            skipWhitespace()
            object[key] = try parseValue(depth: depth)
            skipWhitespace()
            guard position < buffer.count else { throw unexpected() }
            switch buffer[position] {
            case UInt8(ascii: ","):
                position += 1
                skipWhitespace()
            case UInt8(ascii: "}"):
                position += 1
                return .object(object)
            default:
                throw unexpected()
            }
        }
    }

    mutating func parseArray(depth: Int) throws -> JSONValue {
        guard depth <= JSONParser.maxDepth else { throw error("nesting deeper than \(JSONParser.maxDepth)") }
        position += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if position < buffer.count, buffer[position] == UInt8(ascii: "]") {
            position += 1
            return .array(items)
        }
        while true {
            items.append(try parseValue(depth: depth))
            skipWhitespace()
            guard position < buffer.count else { throw unexpected() }
            switch buffer[position] {
            case UInt8(ascii: ","):
                position += 1
                skipWhitespace()
            case UInt8(ascii: "]"):
                position += 1
                return .array(items)
            default:
                throw unexpected()
            }
        }
    }

    mutating func parseNumber() throws -> JSONValue {
        let start = position
        var negative = false
        if buffer[position] == UInt8(ascii: "-") {
            negative = true
            position += 1
        }
        guard position < buffer.count, isDigit(buffer[position]) else { throw unexpected() }
        var mantissa: UInt64 = 0
        var significantDigits = 0
        var overflowed = false
        if buffer[position] == UInt8(ascii: "0") {
            position += 1
        } else {
            while position < buffer.count, isDigit(buffer[position]) {
                accumulate(buffer[position], into: &mantissa, digits: &significantDigits, overflowed: &overflowed)
                position += 1
            }
        }
        var fractionDigits = 0
        if position < buffer.count, buffer[position] == UInt8(ascii: ".") {
            position += 1
            guard position < buffer.count, isDigit(buffer[position]) else { throw unexpected() }
            while position < buffer.count, isDigit(buffer[position]) {
                accumulate(buffer[position], into: &mantissa, digits: &significantDigits, overflowed: &overflowed)
                fractionDigits += 1
                position += 1
            }
        }
        var exponent = 0
        if position < buffer.count, buffer[position] == UInt8(ascii: "e") || buffer[position] == UInt8(ascii: "E") {
            position += 1
            var exponentNegative = false
            if position < buffer.count, buffer[position] == UInt8(ascii: "+") || buffer[position] == UInt8(ascii: "-") {
                exponentNegative = buffer[position] == UInt8(ascii: "-")
                position += 1
            }
            guard position < buffer.count, isDigit(buffer[position]) else { throw unexpected() }
            while position < buffer.count, isDigit(buffer[position]) {
                if exponent < 100_000 { exponent = exponent * 10 + Int(buffer[position] - 0x30) }
                position += 1
            }
            if exponentNegative { exponent = -exponent }
        }
        let scale = exponent - fractionDigits
        if !overflowed, significantDigits <= 15, scale >= -22, scale <= 22 {
            var value = Double(mantissa)
            if scale > 0 { value *= Parser.powersOfTen[scale] } else if scale < 0 { value /= Parser.powersOfTen[-scale] }
            return .number(negative ? -value : value)
        }
        let text = String(decoding: UnsafeBufferPointer(rebasing: buffer[start..<position]), as: UTF8.self)
        guard let value = Double(text) else { throw error("number out of range", at: start) }
        return .number(value)
    }

    static let powersOfTen: [Double] = (0...22).map { exponent in
        var v = 1.0
        for _ in 0..<exponent { v *= 10 }
        return v
    }

    func accumulate(_ byte: UInt8, into mantissa: inout UInt64, digits: inout Int, overflowed: inout Bool) {
        if mantissa == 0, byte == UInt8(ascii: "0") { return }
        digits += 1
        if digits > 19 {
            overflowed = true
            return
        }
        mantissa = mantissa * 10 + UInt64(byte - 0x30)
    }

    mutating func parseString() throws -> JSONValue {
        position += 1
        let start = position
        while position < buffer.count {
            let byte = buffer[position]
            if byte == UInt8(ascii: "\"") {
                if let bad = Parser.firstInvalidUTF8(buffer, from: start, to: position) {
                    throw error("invalid UTF-8", at: bad)
                }
                let text = String(decoding: UnsafeBufferPointer(rebasing: buffer[start..<position]), as: UTF8.self)
                position += 1
                return .string(text)
            }
            if byte == UInt8(ascii: "\\") { return try parseEscapedString(start: start) }
            if byte < 0x20 { throw error("control character in string") }
            position += 1
        }
        throw error("unterminated string", at: start - 1)
    }

    mutating func parseEscapedString(start: Int) throws -> JSONValue {
        scratch.removeAll(keepingCapacity: true)
        var runStart = start
        var hasLoneSurrogate = false
        while position < buffer.count {
            let byte = buffer[position]
            if byte == UInt8(ascii: "\"") {
                try copyRun(from: runStart, to: position)
                position += 1
                return hasLoneSurrogate ? .utf16String(Parser.decodeWTF8(scratch)) : .string(String(decoding: scratch, as: UTF8.self))
            }
            if byte == UInt8(ascii: "\\") {
                try copyRun(from: runStart, to: position)
                position += 1
                guard position < buffer.count else { throw unexpected() }
                switch buffer[position] {
                case UInt8(ascii: "\""): scratch.append(0x22)
                case UInt8(ascii: "\\"): scratch.append(0x5C)
                case UInt8(ascii: "/"): scratch.append(0x2F)
                case UInt8(ascii: "b"): scratch.append(0x08)
                case UInt8(ascii: "f"): scratch.append(0x0C)
                case UInt8(ascii: "n"): scratch.append(0x0A)
                case UInt8(ascii: "r"): scratch.append(0x0D)
                case UInt8(ascii: "t"): scratch.append(0x09)
                case UInt8(ascii: "u"):
                    position += 1
                    var unit = try hex4()
                    if (0xD800...0xDBFF).contains(unit),
                       position + 6 <= buffer.count,
                       buffer[position] == UInt8(ascii: "\\"), buffer[position + 1] == UInt8(ascii: "u") {
                        let save = position
                        position += 2
                        let low = try hex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            position = save
                        }
                    }
                    if (0xD800...0xDFFF).contains(unit) { hasLoneSurrogate = true }
                    appendWTF8(scalar: unit, to: &scratch)
                    runStart = position
                    continue
                default: throw error("invalid escape")
                }
                position += 1
                runStart = position
                continue
            }
            if byte < 0x20 { throw error("control character in string") }
            position += 1
        }
        throw error("unterminated string", at: start - 1)
    }

    mutating func copyRun(from: Int, to: Int) throws {
        guard from < to else { return }
        if let bad = Parser.firstInvalidUTF8(buffer, from: from, to: to) { throw error("invalid UTF-8", at: bad) }
        scratch.append(contentsOf: UnsafeBufferPointer(rebasing: buffer[from..<to]))
    }

    mutating func hex4() throws -> UInt32 {
        guard position + 4 <= buffer.count else { throw error("unexpected end of input", at: buffer.count) }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = buffer[position]
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - 0x30)
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - 0x61 + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - 0x41 + 10)
            default: throw error("invalid unicode escape")
            }
            value = value << 4 | digit
            position += 1
        }
        return value
    }

    func appendWTF8(scalar: UInt32, to out: inout [UInt8]) {
        switch scalar {
        case 0..<0x80:
            out.append(UInt8(scalar))
        case 0x80..<0x800:
            out.append(UInt8(0xC0 | scalar >> 6))
            out.append(UInt8(0x80 | scalar & 0x3F))
        case 0x800..<0x10000:
            out.append(UInt8(0xE0 | scalar >> 12))
            out.append(UInt8(0x80 | scalar >> 6 & 0x3F))
            out.append(UInt8(0x80 | scalar & 0x3F))
        default:
            out.append(UInt8(0xF0 | scalar >> 18))
            out.append(UInt8(0x80 | scalar >> 12 & 0x3F))
            out.append(UInt8(0x80 | scalar >> 6 & 0x3F))
            out.append(UInt8(0x80 | scalar & 0x3F))
        }
    }

    static func decodeWTF8(_ bytes: [UInt8]) -> [UInt16] {
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            let b0 = UInt32(bytes[i])
            var scalar: UInt32
            var length: Int
            if b0 < 0x80 { scalar = b0; length = 1 }
            else if b0 < 0xE0 { scalar = b0 & 0x1F; length = 2 }
            else if b0 < 0xF0 { scalar = b0 & 0x0F; length = 3 }
            else { scalar = b0 & 0x07; length = 4 }
            for k in 1..<length { scalar = scalar << 6 | UInt32(bytes[i + k]) & 0x3F }
            i += length
            if scalar < 0x10000 {
                units.append(UInt16(scalar))
            } else {
                let v = scalar - 0x10000
                units.append(UInt16(0xD800 + (v >> 10)))
                units.append(UInt16(0xDC00 + (v & 0x3FF)))
            }
        }
        return units
    }

    static func firstInvalidUTF8(_ buffer: UnsafeBufferPointer<UInt8>, from: Int, to: Int) -> Int? {
        var i = from
        while i < to {
            let b0 = buffer[i]
            if b0 < 0x80 { i += 1; continue }
            let length: Int
            var secondLow: UInt8 = 0x80
            var secondHigh: UInt8 = 0xBF
            switch b0 {
            case 0xC2...0xDF: length = 2
            case 0xE0: length = 3; secondLow = 0xA0
            case 0xE1...0xEC, 0xEE, 0xEF: length = 3
            case 0xED: length = 3; secondHigh = 0x9F
            case 0xF0: length = 4; secondLow = 0x90
            case 0xF1...0xF3: length = 4
            case 0xF4: length = 4; secondHigh = 0x8F
            default: return i
            }
            guard i + length <= to else { return i }
            let b1 = buffer[i + 1]
            guard b1 >= secondLow, b1 <= secondHigh else { return i }
            for k in 2..<length where buffer[i + k] & 0xC0 != 0x80 { return i }
            i += length
        }
        return nil
    }
}

private func isDigit(_ byte: UInt8) -> Bool {
    byte >= 0x30 && byte <= 0x39
}

private func hex(_ byte: UInt8) -> String {
    let digits = Array("0123456789abcdef".utf8)
    return String(decoding: [digits[Int(byte >> 4)], digits[Int(byte & 0xF)]], as: UTF8.self)
}
