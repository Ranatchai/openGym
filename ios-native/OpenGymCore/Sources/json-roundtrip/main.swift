import Foundation
import OpenGymCore

let input = FileHandle.standardInput.readDataToEndOfFile()
do {
    let value = try JSONParser.parse(Array(input))
    FileHandle.standardOutput.write(Data(JSONSerializer.serialize(value)))
} catch let error as JSONParseError {
    FileHandle.standardError.write(Data("error: \(error.description)\n".utf8))
    exit(1)
}
