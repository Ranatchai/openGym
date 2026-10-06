import Testing
import OpenGymCore

@Suite struct JSONRoundTripTests {
    @Test func corpusIsPresent() {
        let cases = Corpus.pairs.filter { $0.name.hasPrefix("cases/") }.count
        let random = Corpus.pairs.count - cases
        print("JSONRoundTripTests: \(Corpus.pairs.count) corpus files (\(cases) cases, \(random) random), \(Corpus.edits.count) edits, \(Corpus.malformed.count) malformed")
        #expect(cases >= 20)
        #expect(random == 500)
        #expect(Corpus.edits.count >= 7)
        #expect(Corpus.malformed.count >= 15)
    }

    @Test(arguments: Corpus.pairs)
    func testCorpusIsByteIdentical(pair: CorpusPair) throws {
        let output = JSONSerializer.serialize(try JSONParser.parse(pair.input))
        #expect(output == pair.expected, "\(pair.name): \(firstDifference(output, pair.expected))")
    }

    @Test(arguments: Corpus.pairs)
    func expectedIsAFixedPoint(pair: CorpusPair) throws {
        let output = JSONSerializer.serialize(try JSONParser.parse(pair.expected))
        #expect(output == pair.expected, "\(pair.name): \(firstDifference(output, pair.expected))")
    }

    @Test(arguments: Corpus.malformed)
    func malformedInputIsRejectedWithAnOffset(malformed: MalformedCase) {
        #expect(throws: JSONParseError.self, "\(malformed.name) parsed") {
            try JSONParser.parse(malformed.input)
        }
    }
}

@Suite struct StateDocumentTests {
    @Test(arguments: Corpus.edits)
    func testStateDocumentEditKeepsUnknownKeys(edit: EditCase) throws {
        var document = try StateDocument(parsing: edit.input)
        for (key, value) in edit.edit.ordered {
            switch key {
            case "unit":
                guard let unit = value.stringValue.flatMap(WeightUnit.init(rawValue:)) else { throw StateDocumentError(description: "bad unit in \(edit.name)") }
                document.unit = unit
            case "restSec":
                guard let n = value.numberValue else { throw StateDocumentError(description: "bad restSec in \(edit.name)") }
                document.restSec = n
            case "routines":
                guard let a = value.arrayValue else { throw StateDocumentError(description: "bad routines in \(edit.name)") }
                document.routines = a
            case "workouts":
                guard let a = value.arrayValue else { throw StateDocumentError(description: "bad workouts in \(edit.name)") }
                document.workouts = a
            default:
                throw StateDocumentError(description: "\(edit.name) edits \(key), which StateDocument does not expose")
            }
        }
        let output = document.serialized()
        #expect(output == edit.expected, "\(edit.name): \(firstDifference(output, edit.expected))")
    }

    @Test func readsTypedFieldsAndTreatsOthersAsAbsent() throws {
        var document = try StateDocument(parsing: Array(#"{"unit":"lb","restSec":75,"routines":[{"id":"r1"}],"x":1}"#.utf8))
        #expect(document.unit == .lb)
        #expect(document.restSec == 75)
        #expect(document.routines.count == 1)
        #expect(document.workouts.isEmpty)
        document.unit = nil
        document.restSec = nil
        #expect(String(decoding: document.serialized(), as: UTF8.self) == #"{"routines":[{"id":"r1"}],"x":1}"#)
    }

    @Test func rejectsANonObjectRoot() {
        #expect(throws: StateDocumentError(description: "state root is not an object")) {
            try StateDocument(parsing: Array("[1]".utf8))
        }
    }
}
