import Foundation

public struct QuerySnapshot<Value: Sendable>: Sendable {
    public var key: QueryKey
    public var status: QueryStatus
    public var isFetching: Bool
    public var data: Value?
    public var error: Error?
    public var updatedAt: Date?
    public var isStale: Bool

    public var isLoading: Bool {
        status == .pending && data == nil
    }

    public var isRefetching: Bool {
        isFetching && data != nil
    }

    public init(
        key: QueryKey,
        status: QueryStatus,
        isFetching: Bool,
        data: Value?,
        error: Error?,
        updatedAt: Date?,
        isStale: Bool
    ) {
        self.key = key
        self.status = status
        self.isFetching = isFetching
        self.data = data
        self.error = error
        self.updatedAt = updatedAt
        self.isStale = isStale
    }

    public static func pending(key: QueryKey) -> QuerySnapshot<Value> {
        QuerySnapshot(
            key: key,
            status: .pending,
            isFetching: false,
            data: nil,
            error: nil,
            updatedAt: nil,
            isStale: true
        )
    }
}

public enum QueryStatus: Sendable, Equatable {
    case pending
    case success
    case failure
}
