import Foundation

public struct MutationDefaultOptions: Sendable {
    public var retry: RetryPolicy
    public var retryDelay: RetryDelay

    public init(
        retry: RetryPolicy = .never,
        retryDelay: RetryDelay = .exponentialBackoff()
    ) {
        self.retry = retry
        self.retryDelay = retryDelay
    }
}

public struct MutationOptions<Variables: Sendable, Value: Sendable, Context: Sendable>: Sendable {
    public var retry: RetryPolicy?
    public var retryDelay: RetryDelay?
    public var onMutate: (@Sendable (Variables) async throws -> Context)?
    public var onSuccess: (@Sendable (Value, Variables, Context?) async -> Void)?
    public var onError: (@Sendable (Error, Variables, Context?) async -> Void)?
    public var onSettled: (@Sendable (Value?, Error?, Variables, Context?) async -> Void)?

    public init(
        retry: RetryPolicy? = nil,
        retryDelay: RetryDelay? = nil,
        onMutate: (@Sendable (Variables) async throws -> Context)? = nil,
        onSuccess: (@Sendable (Value, Variables, Context?) async -> Void)? = nil,
        onError: (@Sendable (Error, Variables, Context?) async -> Void)? = nil,
        onSettled: (@Sendable (Value?, Error?, Variables, Context?) async -> Void)? = nil
    ) {
        self.retry = retry
        self.retryDelay = retryDelay
        self.onMutate = onMutate
        self.onSuccess = onSuccess
        self.onError = onError
        self.onSettled = onSettled
    }
}
