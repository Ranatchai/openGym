import Testing
import OpenGymCore

private func roundTrip(_ text: String) throws -> String {
    JSONSerializer.string(try JSONParser.parse(text))
}

@Suite struct JSONObjectOrderTests {
    @Test func arrayIndexKeysComeFirstAscending() {
        var o = JSONObject()
        o["b"] = .null
        o["20"] = .null
        o["a"] = .null
        o["3"] = .null
        o["01"] = .null
        #expect(o.keys == ["3", "20", "b", "a", "01"])
    }

    @Test func settingAnExistingKeyKeepsItsPlace() {
        var o = JSONObject([("a", .number(1)), ("b", .number(2))])
        o["a"] = .number(3)
        #expect(o.keys == ["a", "b"])
        #expect(o["a"] == .number(3))
    }

    @Test(arguments: [2, 8, 9, 40])
    func removingThenSettingAppends(size: Int) {
        var o = JSONObject((0..<size).map { ("k\($0)", JSONValue.number(Double($0))) })
        o["k0"] = nil
        #expect(o["k0"] == nil)
        #expect(o["k\(size - 1)"] == .number(Double(size - 1)))
        o["k1"] = .number(-1)
        o["k0"] = .number(99)
        #expect(o.keys == (1..<size).map { "k\($0)" } + ["k0"])
        #expect(o["k1"] == .number(-1))
        #expect(o.count == size)
    }

    @Test(arguments: [
        ("0", true), ("7", true), ("4294967294", true), ("4294967295", false), ("01", false),
        ("-1", false), ("1.0", false), ("", false), ("42949672940", false), ("a", false),
    ])
    func arrayIndexRule(key: String, isIndex: Bool) {
        #expect((JSONObject.arrayIndex(key) != nil) == isIndex)
    }
}

@Suite struct NumberFormattingTests {
    @Test(arguments: [
        (0.1, "0.1"), (1e-7, "1e-7"), (1e21, "1e+21"), (1e20, "100000000000000000000"),
        (-0.0, "0"), (5e-324, "5e-324"), (1.7976931348623157e308, "1.7976931348623157e+308"),
        (1784139960000, "1784139960000"), (82.4, "82.4"), (1e16, "10000000000000000"),
        (9007199254740992, "9007199254740992"), (1.5e-6, "0.0000015"), (0.000001, "0.000001"),
        (2.5e-5, "0.000025"), (1e300, "1e+300"), (100, "100"), (-1.5, "-1.5"), (123e-20, "1.23e-18"),
        (123456789012345680000, "123456789012345680000"), (0.30000000000000004, "0.30000000000000004"),
        (Double.infinity, "null"), (-Double.infinity, "null"), (Double.nan, "null"),
    ])
    func matchesJavaScript(value: Double, expected: String) {
        #expect(JSONSerializer.string(.number(value)) == expected)
    }

    @Test func minusZeroParsesNegativeAndPrintsZero() throws {
        let value = try JSONParser.parse("-0")
        #expect(value == .number(-0.0))
        if case .number(let n) = value { #expect(n.sign == .minus) }
        #expect(JSONSerializer.string(value) == "0")
    }

    @Test(arguments: [
        ("1E5", "100000"), ("1e+5", "100000"), ("0.1e1", "1"), ("12345678901234567890", "12345678901234567000"),
        ("2.2250738585072014e-308", "2.2250738585072014e-308"), ("1e400", "null"), ("1e-400", "0"),
        ("0.000025", "0.000025"), ("4.35", "4.35"), ("1.0", "1"),
    ])
    func parsesSpellings(input: String, expected: String) throws {
        #expect(try roundTrip(input) == expected)
    }
}

@Suite struct StringTests {
    @Test func escapesLikeStringify() throws {
        let input = #""\u0000\u001f\b\f\n\r\t\"\\\/\u007f<\/script>""#
        #expect(try roundTrip(input) == #""\u0000\u001f\b\f\n\r\t\"\\/"# + "\u{7f}" + #"</script>""#)
    }

    @Test func keepsLineSeparatorsAndNonASCIIRaw() throws {
        let input = "\"\u{2028}\u{2029}สวัสดี😀\""
        #expect(try roundTrip(input) == input)
        #expect(try roundTrip(#""\ud83d\ude00""#) == "\"😀\"")
    }

    @Test func loneSurrogatesComeBackAsLowercaseEscapes() throws {
        #expect(try roundTrip(#""\uD83D""#) == #""\ud83d""#)
        #expect(try roundTrip(#""\uDE00x""#) == #""\ude00x""#)
        #expect(try roundTrip(#""a\ud83d\u0041""#) == #""a\ud83dA""#)
        let value = try JSONParser.parse(#""\ud83d""#)
        #expect(value == .utf16String([0xD83D]))
    }

    @Test func loneSurrogateKeysParseLikeJSONParse() throws {
        #expect(try roundTrip(#"{"\ud800":1}"#) == #"{"\ud800":1}"#)
        #expect(try roundTrip(#"{"\ud800":1,"\ud800":2,"\udc00":3}"#) == #"{"\ud800":2,"\udc00":3}"#)
    }

    @Test func equalityIsByCodeUnitNotCanonicalEquivalence() {
        let nfc = "\u{E9}"
        let nfd = "e\u{301}"
        #expect(nfc == nfd)
        #expect(JSONValue.string(nfc) != .string(nfd))
        #expect(JSONValue.string(nfc) == .string("\u{E9}"))
        #expect(JSONValue.array([.string(nfc)]) != .array([.string(nfd)]))
        #expect(JSONValue.string("😀") == .utf16String([0xD83D, 0xDE00]))
        #expect(JSONValue.string("a") != .utf16String([0xD83D]))
    }
}

@Suite struct CodeUnitKeyTests {
    @Test(arguments: [0, 20])
    func canonicallyEquivalentKeysStayDistinct(padding: Int) {
        var o = JSONObject((0..<padding).map { ("k\($0)", JSONValue.number(Double($0))) })
        o["\u{E9}"] = .number(1)
        o["e\u{301}"] = .number(2)
        o["\u{212B}"] = .number(3)
        o["\u{C5}"] = .number(4)
        #expect(o.count == padding + 4)
        #expect(o["\u{E9}"] == .number(1))
        #expect(o["e\u{301}"] == .number(2))
        #expect(o["\u{212B}"] == .number(3))
        #expect(o["\u{C5}"] == .number(4))
        o["e\u{301}"] = nil
        #expect(o.count == padding + 3)
        #expect(o["\u{E9}"] == .number(1))
        #expect(o["e\u{301}"] == nil)
    }

    @Test func objectsWithEquivalentButDifferentKeysAreNotEqual() {
        #expect(JSONObject([("\u{E9}", .null)]) != JSONObject([("e\u{301}", .null)]))
    }

    @Test func loneSurrogateKeysLookUpByCodeUnits() throws {
        guard case .object(var o) = try JSONParser.parse(#"{"\ud800":1,"\udc00":2,"\ud83d\ude00":3}"#) else { throw JSONParseError(offset: 0, message: "not an object") }
        let high = JSONKey(utf16: [0xD800])
        #expect(o[high] == .number(1))
        #expect(o[JSONKey(utf16: [0xDC00])] == .number(2))
        #expect(o[JSONKey(utf16: [0xD83D, 0xDE00])] == .number(3))
        #expect(o["😀"] == .number(3))
        #expect(high.string == nil)
        #expect(high.utf16 == [0xD800])
        #expect(JSONKey(utf16: [0xD83D, 0xDE00]).string == "😀")
        #expect(o.keys.map(\.description) == ["\u{FFFD}", "\u{FFFD}", "😀"])
        o[high] = .number(9)
        o[JSONKey(utf16: [0xDC00])] = nil
        #expect(JSONSerializer.string(.object(o)) == #"{"\ud800":9,"😀":3}"#)
    }

    @Test func keysWorkAsLiteralsAndInterpolations() {
        var o = JSONObject()
        for i in 0..<3 { o["k\(i)"] = .number(Double(i)) }
        #expect(o.keys == ["k0", "k1", "k2"])
        #expect(o.keys == (0..<3).map { "k\($0)" })
        #expect(o[JSONKey("k1")] == .number(1))
        #expect(JSONKey("a") == "a")
        #expect(JSONKey("\u{E9}") != JSONKey("e\u{301}"))
        #expect(JSONKey("\u{E9}").hashValue != JSONKey("e\u{301}").hashValue)
        var set: Set<JSONKey> = ["\u{E9}", "e\u{301}"]
        set.insert("\u{E9}")
        #expect(set.count == 2)
    }

    @Test(arguments: [
        (#"{"\#u{E9}":1,"e\#u{301}":2}"#, #"{"\#u{E9}":1,"e\#u{301}":2}"#),
        (#"{"\u00e9":1,"e\u0301":2}"#, #"{"\#u{E9}":1,"e\#u{301}":2}"#),
        (#"{"\#u{212B}":1,"\#u{C5}":2,"A\#u{30A}":3}"#, #"{"\#u{212B}":1,"\#u{C5}":2,"A\#u{30A}":3}"#),
    ])
    func parserKeepsCanonicallyEquivalentKeys(input: String, expected: String) throws {
        #expect(try roundTrip(input) == expected)
    }

    @Test func rejectsInvalidUTF8AtItsOffset() {
        #expect(throws: JSONParseError(offset: 3, message: "invalid UTF-8")) {
            try JSONParser.parse([0x22, 0x61, 0x62, 0xED, 0xA0, 0x80, 0x22])
        }
    }
}

@Suite struct ParserErrorTests {
    @Test(arguments: [
        ("[1,2,]", 5), ("{\"a\":1,}", 7), ("{\"a\":1", 6), ("\"abc", 0), ("", 0), ("\u{FEFF}{}", 0),
        ("{'a':1}", 1), ("NaN", 0), ("01", 1), ("0x10", 1), ("+1", 0), ("\"a\u{01}\"", 2),
        ("\"\\x\"", 2), ("{} x", 3), ("{a:1}", 1), ("1.", 2), ("1e", 2), ("// c\n1", 0),
    ])
    func reportsByteOffset(input: String, offset: Int) {
        do {
            _ = try JSONParser.parse(input)
            Issue.record("parsed \(input) without an error")
        } catch let error as JSONParseError {
            #expect(error.offset == offset, "\(input): \(error)")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func duplicateKeysKeepLastValueAtFirstPosition() throws {
        #expect(try roundTrip(#"{"a":1,"b":2,"a":3,"1":4,"c":5,"1":6}"#) == #"{"1":6,"a":3,"b":2,"c":5}"#)
    }

    @Test func nestingLimitIsAnError() {
        let deep = String(repeating: "[", count: 3000)
        #expect(throws: JSONParseError.self) { try JSONParser.parse(deep) }
    }
}
