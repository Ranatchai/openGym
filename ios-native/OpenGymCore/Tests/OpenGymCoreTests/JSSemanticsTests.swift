import Testing
import OpenGymCore

/// Expected values are what Node 24 prints for the same expressions.
@Suite struct JSSemanticsTests {
    @Test(arguments: [
        ("", "0"), (" 12 ", "12"), ("0x1A", "26"), ("-0x1A", "NaN"), ("0b101", "5"), ("1e3", "1000"),
        (".5", "0.5"), ("5.", "5"), ("+7", "7"), ("-Infinity", "-Infinity"), ("Infinity", "Infinity"),
        ("inf", "NaN"), ("1_000", "NaN"), ("12px", "NaN"), ("\u{a0}12\u{2028}", "12"), ("\u{85}12", "NaN"),
    ])
    func stringToNumber(input: String, expected: String) {
        #expect(JS.numberToString(JS.toNumber(.string(input))) == expected)
    }

    @Test func nonStringToNumber() {
        #expect(JS.toNumber(.array([])) == 0)
        #expect(JS.toNumber(.array([.number(5)])) == 5)
        #expect(JS.toNumber(.array([.number(1), .number(2)])).isNaN)
        #expect(JS.toNumber(.null) == 0)
        #expect(JS.toNumber(.bool(true)) == 1)
        #expect(JS.toNumber(.object(JSONObject())).isNaN)
        #expect(JS.toNumber(nil).isNaN)
    }

    @Test(arguments: [(-2.5, -2.0), (2.5, 3), (0.49999999999999994, 0), (1.5, 2), (-1.5, -1)])
    func round(x: Double, expected: Double) {
        #expect(JS.round(x) == expected)
    }

    @Test func roundKeepsNegativeZero() {
        #expect(JS.round(-0.5).sign == .minus)
        #expect(JS.round(-0.4).sign == .minus)
    }

    @Test func maxAndMinOrderSignedZerosAndPropagateNaN() {
        #expect(JS.max(-0.0, 0).sign == .plus)
        #expect(JS.min(0, -0.0).sign == .minus)
        #expect(JS.max(1, .nan).isNaN)
    }
}
