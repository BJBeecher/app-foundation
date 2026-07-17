public struct Fetch<Value: Sendable>: Sendable {
    public let key: QueryKey
    public let options: FetchOptions?
    public let operation: @Sendable () async throws -> Value

    public init(
        key: QueryKey,
        options: FetchOptions? = nil,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        self.key = key
        self.options = options
        self.operation = operation
    }
}

public extension Fetch {
    @MainActor
    func state(using client: QueryClient) -> FetchState<Value> {
        let state = FetchState(
            fetch: self,
            refetchOperation: { try await client.fetch(self) }
        )
        state.start(updates: client.snapshots(for: self))
        return state
    }
}

public extension Fetch where Value: Codable {
    @MainActor
    func state(using client: QueryClient) -> FetchState<Value> {
        let state = FetchState(
            fetch: self,
            refetchOperation: { try await client.fetch(self) }
        )
        state.start(updates: client.persistentSnapshots(for: self))
        return state
    }
}
