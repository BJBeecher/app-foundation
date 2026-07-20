import Observation
import SwiftUI

@MainActor
public struct Query<Value: Codable & Sendable> {
    public let snapshot: QuerySnapshot<Value>
    private let refetchOperation: () async throws -> Value

    init(
        snapshot: QuerySnapshot<Value>,
        refetch: @escaping () async throws -> Value
    ) {
        self.snapshot = snapshot
        self.refetchOperation = refetch
    }

    public var key: QueryKey { snapshot.key }
    public var data: Value? { snapshot.data }
    public var error: Error? { snapshot.error }
    public var status: QueryStatus { snapshot.status }
    public var isFetching: Bool { snapshot.isFetching }
    public var isLoading: Bool { snapshot.isLoading }
    public var isRefetching: Bool { snapshot.isRefetching }
    public var isStale: Bool { snapshot.isStale }

    @discardableResult
    public func refetch() async throws -> Value {
        try await refetchOperation()
    }
}

@propertyWrapper
@MainActor
public struct QueryState<Value: Codable & Sendable>: @preconcurrency DynamicProperty {
    @Environment(\.queryClient) private var queryClient
    @State private var storage: QueryStateStorage<Value>

    private let fetch: Fetch<Value>

    public init(_ fetch: Fetch<Value>) {
        self.fetch = fetch
        self._storage = State(initialValue: QueryStateStorage(fetch: fetch))
    }

    public var wrappedValue: Query<Value> {
        Query(snapshot: storage.snapshot) {
            try await storage.refetch()
        }
    }

    public mutating func update() {
        storage.bind(fetch: fetch, client: queryClient)
    }
}

@MainActor
@Observable
private final class QueryStateStorage<Value: Codable & Sendable> {
    private(set) var snapshot: QuerySnapshot<Value>

    @ObservationIgnored private var fetch: Fetch<Value>
    @ObservationIgnored private var client: QueryClient?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var bindingID: QueryStateBindingID?

    init(fetch: Fetch<Value>) {
        self.fetch = fetch
        self.snapshot = .pending(key: fetch.key)
    }

    func bind(fetch: Fetch<Value>, client: QueryClient) {
        let bindingID = QueryStateBindingID(
            client: ObjectIdentifier(client),
            key: fetch.key
        )
        guard self.bindingID != bindingID else { return }

        observationTask?.cancel()

        if snapshot.key != fetch.key {
            snapshot = .pending(key: fetch.key)
        }
        self.bindingID = bindingID
        self.fetch = fetch
        self.client = client
        self.observationTask = Task { [weak self] in
            for await snapshot in client.persistentSnapshots(for: fetch) {
                guard !Task.isCancelled else { return }
                self?.snapshot = snapshot
            }
        }
    }

    func refetch() async throws -> Value {
        guard let client else {
            throw QueryStateError.notBound
        }
        return try await client.fetch(fetch)
    }

    deinit {
        observationTask?.cancel()
    }
}

private struct QueryStateBindingID: Equatable {
    let client: ObjectIdentifier
    let key: QueryKey
}

public enum QueryStateError: Error, Sendable, Equatable {
    case notBound
}
