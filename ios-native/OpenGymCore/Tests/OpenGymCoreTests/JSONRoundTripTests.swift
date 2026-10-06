import Testing
@testable import OpenGymCore

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
}
