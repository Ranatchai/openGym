public enum WeightUnit: String, Sendable, CaseIterable {
    case kg, lb
}

public struct StateDocumentError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

/// The persisted openGym state `S` as the web app wrote it. Reads and writes go through the
/// ordered root object, so every key this type does not know stays where it was and every
/// byte that is not edited serializes back unchanged.
public struct StateDocument: Equatable, Sendable {
    public private(set) var root: JSONObject

    public init(root: JSONObject) {
        self.root = root
    }

    public init(parsing bytes: [UInt8]) throws {
        guard case .object(let object) = try JSONParser.parse(bytes) else {
            throw StateDocumentError(description: "state root is not an object")
        }
        root = object
    }

    public func serialized() -> [UInt8] {
        JSONSerializer.serialize(.object(root))
    }

    /// `S.unit`. nil when the key is absent or holds something that is not `kg` or `lb`.
    /// Setting nil removes the key.
    public var unit: WeightUnit? {
        get { root["unit"]?.stringValue.flatMap(WeightUnit.init(rawValue:)) }
        set { root["unit"] = newValue.map { .string($0.rawValue) } }
    }

    /// `S.restSec`. nil when absent or not a number. Setting nil removes the key.
    public var restSec: Double? {
        get { root["restSec"]?.numberValue }
        set { root["restSec"] = newValue.map(JSONValue.number) }
    }

    /// `S.routines`. An absent or non-array value reads as empty, as the store's DEF overlay does.
    public var routines: [JSONValue] {
        get { root["routines"]?.arrayValue ?? [] }
        set { root["routines"] = .array(newValue) }
    }

    /// `S.workouts`. An absent or non-array value reads as empty, as the store's DEF overlay does.
    public var workouts: [JSONValue] {
        get { root["workouts"]?.arrayValue ?? [] }
        set { root["workouts"] = .array(newValue) }
    }
}
