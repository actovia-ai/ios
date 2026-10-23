import Foundation

/// A field of a partial update, where leaving a field out and sending `null` mean different things: absent keeps the
/// stored value, null clears it.
public enum Patch<T: Sendable & Equatable>: Sendable, Equatable {
    case absent
    case null
    case value(T)

    /// The patched value of `current`.
    public func applied(to current: T?) -> T? {
        switch self {
        case .absent: current
        case .null: nil
        case .value(let value): value
        }
    }
}

extension KeyedDecodingContainer {
    func patch<T: Decodable & Sendable & Equatable>(_ type: T.Type, forKey key: Key) throws -> Patch<T> {
        guard contains(key) else { return .absent }
        if try decodeNil(forKey: key) { return .null }
        return .value(try decode(T.self, forKey: key))
    }
}

/// A status the wire names by string: a value this build does not know decodes as `unknown`, never fails the row.
protocol WireEnum: RawRepresentable<String>, Decodable {
    static var unknownCase: Self { get }
}

extension WireEnum {
    init(wire decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.unknownCase
    }
}
