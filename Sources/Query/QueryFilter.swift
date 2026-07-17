import Foundation

public struct QueryFilter: Sendable {
    public var key: QueryKey?
    public var exact: Bool
    public var predicate: (@Sendable (QueryInfo) -> Bool)?

    public init(
        key: QueryKey? = nil,
        exact: Bool = false,
        predicate: (@Sendable (QueryInfo) -> Bool)? = nil
    ) {
        self.key = key
        self.exact = exact
        self.predicate = predicate
    }

    public static var all: QueryFilter {
        QueryFilter()
    }
}

public struct QueryInfo: Sendable {
    public var key: QueryKey
    public var status: QueryStatus
    public var isFetching: Bool
    public var updatedAt: Date?
    public var isActive: Bool
    public var isStale: Bool
}

public enum QueryRefetchBehavior: Sendable, Equatable {
    case none
    case active
    case all
}
