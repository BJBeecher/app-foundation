import Foundation

public struct QueryKey: Hashable, Codable, Sendable, ExpressibleByArrayLiteral, CustomStringConvertible {
    public var parts: [QueryKeyPart]

    public init(_ parts: [QueryKeyPart]) {
        self.parts = parts
    }

    public init(arrayLiteral elements: QueryKeyPart...) {
        self.parts = elements
    }

    public var description: String {
        parts.map(\.description).joined(separator: "/")
    }

    public func starts(with prefix: QueryKey) -> Bool {
        guard prefix.parts.count <= parts.count else { return false }
        return zip(parts, prefix.parts).allSatisfy(==)
    }
}

public enum QueryKeyPart: Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case bool(Bool)
    case uuid(UUID)

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    public var description: String {
        switch self {
        case let .string(value):
            value
        case let .int(value):
            String(value)
        case let .bool(value):
            String(value)
        case let .uuid(value):
            value.uuidString
        }
    }
}
