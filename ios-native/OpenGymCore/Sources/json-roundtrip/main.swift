import Foundation
import OpenGymCore

func run() -> Int32 {
    var arguments = Array(CommandLine.arguments.dropFirst())
    var unit: WeightUnit?
    var restSec: Double?
    while !arguments.isEmpty {
        let flag = arguments.removeFirst()
        guard !arguments.isEmpty else { return usage("\(flag) needs a value") }
        let value = arguments.removeFirst()
        switch flag {
        case "--unit":
            guard let parsed = WeightUnit(rawValue: value) else { return usage("--unit takes kg or lb") }
            unit = parsed
        case "--rest-sec":
            guard let parsed = Double(value) else { return usage("--rest-sec takes a number") }
            restSec = parsed
        default:
            return usage("unknown flag \(flag)")
        }
    }
    let input = Array(FileHandle.standardInput.readDataToEndOfFile())
    do {
        let output: [UInt8]
        if unit != nil || restSec != nil {
            var document = try StateDocument(parsing: input)
            if let unit { document.unit = unit }
            if let restSec { document.restSec = restSec }
            output = document.serialized()
        } else {
            output = JSONSerializer.serialize(try JSONParser.parse(input))
        }
        FileHandle.standardOutput.write(Data(output))
        return 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
}

func usage(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data("json-roundtrip: \(message)\nusage: json-roundtrip [--unit kg|lb] [--rest-sec N] < input.json\n".utf8))
    return 2
}

exit(run())
