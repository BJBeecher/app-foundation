import Foundation

public protocol RateLimiter: Sendable {
    func limit(_ request: String, delay: Duration, block: @escaping @Sendable () async throws -> Void) async throws
}

public actor DefaultRateLimiter: RateLimiter {
    private var requestIds = [String: UUID]()

    public init() {}

    public func limit(_ request: String, delay: Duration, block: @escaping @Sendable () async throws -> Void) async throws {
        let requestId = UUID()
        requestIds[request] = requestId
        try await Task.sleep(for: delay)

        if requestIds[request] == requestId {
            try await block()
        }
    }
}
