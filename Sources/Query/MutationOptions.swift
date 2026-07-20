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

public struct MutationOptions<Variables: Sendable, Value: Sendable>: Sendable {
    public var retry: RetryPolicy?
    public var retryDelay: RetryDelay?
    public let mutationFn: @Sendable (Variables) async throws -> Value

    let onMutate: (@Sendable (Variables) async throws -> (any Sendable)?)?
    let onSuccess: (@Sendable (Value, Variables, (any Sendable)?) async -> Void)?
    let onError: (@Sendable (Error, Variables, (any Sendable)?) async -> Void)?
    let onSettled: (@Sendable (Value?, Error?, Variables, (any Sendable)?) async -> Void)?

    public init(
        retry: RetryPolicy? = nil,
        retryDelay: RetryDelay? = nil,
        onSuccess: (@Sendable (Value, Variables, Void?) async -> Void)? = nil,
        onError: (@Sendable (Error, Variables, Void?) async -> Void)? = nil,
        onSettled: (@Sendable (Value?, Error?, Variables, Void?) async -> Void)? = nil,
        mutationFn: @escaping @Sendable (Variables) async throws -> Value
    ) {
        self.retry = retry
        self.retryDelay = retryDelay
        self.mutationFn = mutationFn
        self.onMutate = nil
        if let onSuccess {
            self.onSuccess = { value, variables, _ in
                await onSuccess(value, variables, nil)
            }
        } else {
            self.onSuccess = nil
        }
        if let onError {
            self.onError = { error, variables, _ in
                await onError(error, variables, nil)
            }
        } else {
            self.onError = nil
        }
        if let onSettled {
            self.onSettled = { value, error, variables, _ in
                await onSettled(value, error, variables, nil)
            }
        } else {
            self.onSettled = nil
        }
    }

    public init<OnMutateResult: Sendable>(
        retry: RetryPolicy? = nil,
        retryDelay: RetryDelay? = nil,
        onMutate: @escaping @Sendable (Variables) async throws -> OnMutateResult,
        onSuccess: (@Sendable (Value, Variables, OnMutateResult?) async -> Void)? = nil,
        onError: (@Sendable (Error, Variables, OnMutateResult?) async -> Void)? = nil,
        onSettled: (@Sendable (Value?, Error?, Variables, OnMutateResult?) async -> Void)? = nil,
        mutationFn: @escaping @Sendable (Variables) async throws -> Value
    ) {
        self.retry = retry
        self.retryDelay = retryDelay
        self.mutationFn = mutationFn
        self.onMutate = { variables in try await onMutate(variables) }
        if let onSuccess {
            self.onSuccess = { value, variables, result in
                await onSuccess(value, variables, result as? OnMutateResult)
            }
        } else {
            self.onSuccess = nil
        }
        if let onError {
            self.onError = { error, variables, result in
                await onError(error, variables, result as? OnMutateResult)
            }
        } else {
            self.onError = nil
        }
        if let onSettled {
            self.onSettled = { value, error, variables, result in
                await onSettled(value, error, variables, result as? OnMutateResult)
            }
        } else {
            self.onSettled = nil
        }
    }
}
