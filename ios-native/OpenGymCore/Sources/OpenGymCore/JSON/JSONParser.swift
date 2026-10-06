public struct JSONParseError: Error, Equatable, CustomStringConvertible {
    public let offset: Int
    public let message: String

    public var description: String { "\(message) at byte \(offset)" }
}

public enum JSONParser {
    public static func parse(_ bytes: [UInt8]) throws -> JSONValue {
        throw JSONParseError(offset: 0, message: "parser not written yet")
    }
}
