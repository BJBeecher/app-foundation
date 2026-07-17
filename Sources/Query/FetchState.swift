import Observation

@MainActor
@Observable
public final class FetchState<Value: Sendable> {
    public private(set) var snapshot: QuerySnapshot<Value>

    public var data: Value? { snapshot.data }
    public var error: Error? { snapshot.error }
    public var status: QueryStatus { snapshot.status }
    public var isFetching: Bool { snapshot.isFetching }
    public var isLoading: Bool { snapshot.isLoading }
    public var isRefetching: Bool { snapshot.isRefetching }
    public var isStale: Bool { snapshot.isStale }

    @ObservationIgnored private let refetchOperation: @Sendable () async throws -> Value
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(
        fetch: Fetch<Value>,
        refetchOperation: @escaping @Sendable () async throws -> Value
    ) {
        self.snapshot = .pending(key: fetch.key)
        self.refetchOperation = refetchOperation
    }

    func start(updates: AsyncStream<QuerySnapshot<Value>>) {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                self?.snapshot = snapshot
            }
        }
    }

    func consume(updates: AsyncStream<QuerySnapshot<Value>>) async {
        for await snapshot in updates {
            guard !Task.isCancelled else { return }
            self.snapshot = snapshot
        }
    }

    @discardableResult
    public func refetch() async throws -> Value {
        try await refetchOperation()
    }

    deinit {
        updatesTask?.cancel()
    }
}
