/// One built-in exercise as `CATALOGUE` in `frontend/src/lib/exercises.js` holds it, read from
/// the bundled `exercises.json`. Field names match the web catalogue so ported code reads alike.
public struct Exercise: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let n: String
    public let bp: String
    public let eq: String
    public let tg: String
    public let mg: String
    public let sm: [String]
    public let st: [String]
    public let img: String
    public let gif: String
    public let primaries: [String]?
    public let secondaries: [String]?
}
