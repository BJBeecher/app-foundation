import Foundation

public struct FetchOptions: Sendable {
    public var staleTime: Duration
    public var garbageCollectionTime: Duration?
    public var retry: RetryPolicy
    public var retryDelay: RetryDelay
    public var storage: QueryStorage?

    public init(
        staleTime: Duration = .zero,
        garbageCollectionTime: Duration? = .seconds(300),
        retry: RetryPolicy = .maxAttempts(3),
        retryDelay: RetryDelay = .exponentialBackoff(),
        storage: QueryStorage? = nil
    ) {
        self.staleTime = staleTime
        self.garbageCollectionTime = garbageCollectionTime
        self.retry = retry
        self.retryDelay = retryDelay
        self.storage = storage
    }
}

public enum RetryPolicy: Sendable, Equatable {
    case never
    case maxAttempts(Int)
    case always

    func shouldRetry(afterFailureCount failureCount: Int) -> Bool {
        switch self {
        case .never:
            false
        case let .maxAttempts(maxAttempts):
            failureCount < maxAttempts
        case .always:
            true
        }
    }
}

public struct RetryDelay: Sendable {
    private let duration: @Sendable (_ attempt: Int, _ error: Error) -> Duration

    public init(_ duration: @escaping @Sendable (_ attempt: Int, _ error: Error) -> Duration) {
        self.duration = duration
    }

    public func duration(forAttempt attempt: Int, error: Error) -> Duration {
        duration(attempt, error)
    }

    public static func constant(_ duration: Duration) -> RetryDelay {
        RetryDelay { _, _ in duration }
    }

    public static func exponentialBackoff(
        initial: Duration = .seconds(1),
        maximum: Duration = .seconds(30)
    ) -> RetryDelay {
        RetryDelay { attempt, _ in
            let multiplier = max(1, 1 << max(0, attempt - 1))
            return min(initial * multiplier, maximum)
        }
    }
}
