import Foundation

public actor Mutation<Variables: Sendable, Value: Sendable, Context: Sendable> {
    public private(set) var snapshot: MutationSnapshot<Variables, Value>

    private let options: MutationOptions<Variables, Value, Context>
    private let retry: RetryPolicy
    private let retryDelay: RetryDelay
    private let operation: @Sendable (Variables) async throws -> Value
    private var observers: [UUID: AsyncStream<MutationSnapshot<Variables, Value>>.Continuation] = [:]
    private var latestInvocationID: UUID?

    init(
        defaultOptions: MutationDefaultOptions,
        options: MutationOptions<Variables, Value, Context>,
        operation: @escaping @Sendable (Variables) async throws -> Value
    ) {
        self.options = options
        self.retry = options.retry ?? defaultOptions.retry
        self.retryDelay = options.retryDelay ?? defaultOptions.retryDelay
        self.operation = operation
        self.snapshot = .idle
    }

    public nonisolated func observe() -> AsyncStream<MutationSnapshot<Variables, Value>> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observerID = UUID()
            let task = Task {
                await self.addObserver(id: observerID, continuation: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.removeObserver(id: observerID) }
            }
        }
    }

    @discardableResult
    public func mutate(_ variables: Variables) async throws -> Value {
        let invocationID = UUID()
        latestInvocationID = invocationID
        updateSnapshot(
            .init(
                status: .pending,
                variables: variables,
                data: nil,
                error: nil,
                failureCount: 0
            ),
            for: invocationID
        )

        var context: Context?
        var failureCount = 0

        do {
            context = try await options.onMutate?(variables)

            while true {
                do {
                    try Task.checkCancellation()
                    let value = try await operation(variables)
                    await options.onSuccess?(value, variables, context)
                    await options.onSettled?(value, nil, variables, context)
                    updateSnapshot(
                        .init(
                            status: .success,
                            variables: variables,
                            data: value,
                            error: nil,
                            failureCount: failureCount
                        ),
                        for: invocationID
                    )
                    return value
                } catch {
                    failureCount += 1
                    updateFailureCount(failureCount, for: invocationID)

                    guard retry.shouldRetry(afterFailureCount: failureCount - 1) else {
                        throw error
                    }

                    try await Task.sleep(
                        for: retryDelay.duration(forAttempt: failureCount, error: error)
                    )
                }
            }
        } catch {
            if failureCount == 0 {
                failureCount = 1
            }
            await options.onError?(error, variables, context)
            await options.onSettled?(nil, error, variables, context)
            updateSnapshot(
                .init(
                    status: .failure,
                    variables: variables,
                    data: nil,
                    error: error,
                    failureCount: failureCount
                ),
                for: invocationID
            )
            throw error
        }
    }

    public func reset() {
        latestInvocationID = nil
        snapshot = .idle
        notifyObservers()
    }

    private func addObserver(
        id: UUID,
        continuation: AsyncStream<MutationSnapshot<Variables, Value>>.Continuation
    ) {
        observers[id] = continuation
        continuation.yield(snapshot)
    }

    private func removeObserver(id: UUID) {
        observers[id] = nil
    }

    private func updateSnapshot(
        _ snapshot: MutationSnapshot<Variables, Value>,
        for invocationID: UUID
    ) {
        guard latestInvocationID == invocationID else { return }
        self.snapshot = snapshot
        notifyObservers()
    }

    private func updateFailureCount(_ failureCount: Int, for invocationID: UUID) {
        guard latestInvocationID == invocationID else { return }
        snapshot.failureCount = failureCount
        notifyObservers()
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer.yield(snapshot)
        }
    }
}
