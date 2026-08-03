import Foundation

struct AnyQueryValue: Sendable {
    let value: any Sendable
}

struct QueryRecord {
    var value: (any Sendable)?
    var error: Error?
    var updatedAt: Date?
    var invalidated = false
    var fetchTask: Task<AnyQueryValue, Error>?
    var fetchID: UUID?
    var observerCount = 0
    var unusedAt: Date?
    var options: FetchOptions
    var fetch: (@Sendable () async throws -> AnyQueryValue)?
    var dataRevision: UInt64 = 0

    init(options: FetchOptions) {
        self.options = options
    }
}

struct QueryObserver {
    let yield: @Sendable (QueryRecord, Date) -> Void
}
