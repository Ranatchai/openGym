/// A JSON document as JavaScript holds it after `JSON.parse`.
///
/// Numbers are `Double`, objects keep JS own-key order, and a string that JS can hold but
/// Swift's `String` cannot (one with an unpaired UTF-16 surrogate) has its own case so that
/// `JSON.stringify` parity survives it. Equality compares strings by code unit, as JS does;
/// Swift's `String ==` would treat NFC and NFD spellings as the same value.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    /// A JS string with at least one unpaired surrogate, as UTF-16 code units.
    case utf16String([UInt16])
    case array([JSONValue])
    case object(JSONObject)

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let a), .bool(let b)): a == b
        case (.number(let a), .number(let b)): a == b
        case (.string(let a), .string(let b)): a.utf8.elementsEqual(b.utf8)
        case (.utf16String(let a), .utf16String(let b)): a == b
        case (.string(let a), .utf16String(let b)), (.utf16String(let b), .string(let a)): a.utf16.elementsEqual(b)
        case (.array(let a), .array(let b)): a == b
        case (.object(let a), .object(let b)): a == b
        default: false
        }
    }
}

/// An object key with JS string semantics: compared and hashed by UTF-16 code unit, and able
/// to hold an unpaired surrogate, which `JSON.parse` accepts as a key.
public struct JSONKey: Hashable, Sendable, ExpressibleByStringInterpolation, CustomStringConvertible {
    enum Storage: Sendable {
        case string(String)
        case utf16([UInt16])
    }

    let storage: Storage

    public init(_ string: String) {
        storage = .string(string)
    }

    public init(utf16 units: [UInt16]) {
        if let string = String(validating: units, as: UTF16.self) {
            storage = .string(string)
        } else {
            storage = .utf16(units)
        }
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// nil when the key holds an unpaired surrogate and so has no `String` form.
    public var string: String? {
        if case .string(let s) = storage { return s }
        return nil
    }

    public var utf16: [UInt16] {
        switch storage {
        case .string(let s): Array(s.utf16)
        case .utf16(let units): units
        }
    }

    public var description: String {
        switch storage {
        case .string(let s): s
        case .utf16(let units): String(decoding: units, as: UTF16.self)
        }
    }

    public static func == (lhs: JSONKey, rhs: JSONKey) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.string(let a), .string(let b)): a.utf8.elementsEqual(b.utf8)
        case (.utf16(let a), .utf16(let b)): a == b
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch storage {
        case .string(var s):
            s.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
        case .utf16(let units):
            units.withUnsafeBytes { hasher.combine(bytes: $0) }
        }
    }
}

/// An object whose keys enumerate the way ECMAScript's OrdinaryOwnPropertyKeys does:
/// array-index keys ascending by number, then every other key in insertion order.
///
/// Setting an existing key keeps its position and replaces the value. Removing a key and
/// setting it again appends it, as JS does.
public struct JSONObject: Equatable, Sendable {
    private var entries: [(key: JSONKey, value: JSONValue)]
    private var keyIndex: [JSONKey: Int]?
    private static let scanLimit = 8

    public init() {
        entries = []
    }

    public init(_ pairs: [(JSONKey, JSONValue)]) {
        self.init()
        for (key, value) in pairs { self[key] = value }
    }

    public init(_ pairs: [(String, JSONValue)]) {
        self.init()
        for (key, value) in pairs { self[JSONKey(key)] = value }
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    private func position(of key: JSONKey) -> Int? {
        if let keyIndex { return keyIndex[key] }
        return entries.firstIndex { $0.key == key }
    }

    public subscript(key: JSONKey) -> JSONValue? {
        get {
            guard let index = position(of: key) else { return nil }
            return entries[index].value
        }
        set {
            if let newValue {
                if let index = position(of: key) {
                    entries[index].value = newValue
                } else {
                    keyIndex?[key] = entries.count
                    entries.append((key, newValue))
                    if keyIndex == nil, entries.count > JSONObject.scanLimit { rebuildKeyIndex() }
                }
            } else {
                remove(key)
            }
        }
    }

    public subscript(key: String) -> JSONValue? {
        get { self[JSONKey(key)] }
        set { self[JSONKey(key)] = newValue }
    }

    public mutating func remove(_ key: JSONKey) {
        guard let index = position(of: key) else { return }
        entries.remove(at: index)
        if keyIndex != nil { rebuildKeyIndex() }
    }

    public mutating func remove(_ key: String) {
        remove(JSONKey(key))
    }

    private mutating func rebuildKeyIndex() {
        var built: [JSONKey: Int] = [:]
        built.reserveCapacity(entries.count)
        for (i, entry) in entries.enumerated() { built[entry.key] = i }
        keyIndex = built
    }

    /// Key-value pairs in JS enumeration order.
    public var ordered: [(key: JSONKey, value: JSONValue)] {
        var indexed: [(UInt32, Int)] = []
        var hasIndexKey = false
        for (i, entry) in entries.enumerated() {
            if let n = JSONObject.arrayIndex(entry.key) {
                indexed.append((n, i))
                hasIndexKey = true
            }
        }
        if !hasIndexKey { return entries }
        indexed.sort { $0.0 < $1.0 }
        var result: [(key: JSONKey, value: JSONValue)] = []
        result.reserveCapacity(entries.count)
        for (_, i) in indexed { result.append(entries[i]) }
        for entry in entries where JSONObject.arrayIndex(entry.key) == nil { result.append(entry) }
        return result
    }

    public var keys: [JSONKey] { ordered.map(\.key) }

    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        guard lhs.entries.count == rhs.entries.count else { return false }
        let l = lhs.ordered
        let r = rhs.ordered
        for i in 0..<l.count where l[i].key != r[i].key || l[i].value != r[i].value { return false }
        return true
    }

    static func arrayIndex(_ key: JSONKey) -> UInt32? {
        guard case .string(let s) = key.storage else { return nil }
        return arrayIndex(s)
    }

    /// The canonical array index a key spells, if any: the decimal form of an integer in
    /// `0 ..< 2^32 - 1` with no sign, no leading zero and no other characters.
    public static func arrayIndex(_ key: String) -> UInt32? {
        var utf8 = key.utf8.makeIterator()
        guard let first = utf8.next(), first >= 0x30, first <= 0x39 else { return nil }
        if first == 0x30 { return utf8.next() == nil ? 0 : nil }
        var n: UInt64 = UInt64(first - 0x30)
        var digits = 1
        while let c = utf8.next() {
            guard c >= 0x30, c <= 0x39 else { return nil }
            digits += 1
            if digits > 10 { return nil }
            n = n * 10 + UInt64(c - 0x30)
        }
        return n < 4_294_967_295 ? UInt32(n) : nil
    }
}

extension JSONValue {
    public var objectValue: JSONObject? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
}
