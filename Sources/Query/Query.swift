import Observation
import SwiftUI

@MainActor
public struct Query<Value: Sendable> {
    private let storage: QueryValueStorage<Value>

    fileprivate init(storage: QueryValueStorage<Value>) {
        self.storage = storage
    }

    public var snapshot: QuerySnapshot<Value> {
        QuerySnapshot(
            key: storage.key,
            status: storage.status,
            isFetching: storage.isFetching,
            data: storage.data,
            error: storage.error,
            updatedAt: storage.updatedAt,
            isStale: storage.isStale
        )
    }

    public var key: QueryKey { storage.key }
    public var data: Value? { storage.data }
    public var error: Error? { storage.error }
    public var status: QueryStatus { storage.status }
    public var isFetching: Bool { storage.isFetching }
    public var isLoading: Bool { status == .pending && data == nil }
    public var isRefetching: Bool { isFetching && data != nil }
    public var isStale: Bool { storage.isStale }

    @discardableResult
    public func refetch() async throws -> Value {
        try await storage.refetch()
    }
}

@propertyWrapper
@MainActor
public struct QueryState<Value: Sendable>: @preconcurrency DynamicProperty {
    @Environment(\.queryClient) private var queryClient
    @State private var storage: QueryValueStorage<Value>

    private let bindOperation: @MainActor (QueryValueStorage<Value>, QueryClient) -> Void

    public init(_ fetch: Fetch<Value>) where Value: Codable {
        self._storage = State(initialValue: QueryValueStorage(key: fetch.key))
        self.bindOperation = { storage, client in
            storage.bind(
                fetch: fetch,
                client: client,
                select: { $0 },
                areEqual: nil
            )
        }
    }

    public init<Source: Codable & Sendable>(
        _ fetch: Fetch<Source>,
        select: @escaping @Sendable (Source) -> Value
    ) where Value: Equatable {
        self._storage = State(initialValue: QueryValueStorage(key: fetch.key))
        self.bindOperation = { storage, client in
            storage.bind(
                fetch: fetch,
                client: client,
                select: select,
                areEqual: ==
            )
        }
    }

    public var wrappedValue: Query<Value> {
        Query(storage: storage)
    }

    public mutating func update() {
        bindOperation(storage, queryClient)
    }
}

@MainActor
@Observable
fileprivate final class QueryValueStorage<Value: Sendable> {
    private(set) var key: QueryKey
    private(set) var data: Value?
    private(set) var error: Error?
    private(set) var status: QueryStatus = .pending
    private(set) var isFetching = false
    private(set) var updatedAt: Date?
    private(set) var isStale = true

    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var bindingID: QueryStateBindingID?
    @ObservationIgnored private var refetchOperation: (@Sendable () async throws -> Value)?
    @ObservationIgnored private var dataRevision: UInt64 = 0

    init(key: QueryKey) {
        self.key = key
    }

    func bind<Source: Codable & Sendable>(
        fetch: Fetch<Source>,
        client: QueryClient,
        select: @escaping @Sendable (Source) -> Value,
        areEqual: (@Sendable (Value, Value) -> Bool)?
    ) {
        let bindingID = QueryStateBindingID(
            client: ObjectIdentifier(client),
            key: fetch.key
        )
        guard self.bindingID != bindingID else { return }

        observationTask?.cancel()
        if key != fetch.key {
            reset(key: fetch.key)
        }

        self.bindingID = bindingID
        self.refetchOperation = {
            select(try await client.fetch(fetch))
        }
        self.observationTask = Task { [weak self] in
            for await snapshot in client.observe(fetch) {
                guard !Task.isCancelled else { return }
                self?.apply(snapshot, select: select, areEqual: areEqual)
            }
        }
    }

    func refetch() async throws -> Value {
        guard let refetchOperation else {
            throw QueryStateError.notBound
        }
        return try await refetchOperation()
    }

    private func apply<Source: Sendable>(
        _ snapshot: QuerySnapshot<Source>,
        select: @Sendable (Source) -> Value,
        areEqual: (@Sendable (Value, Value) -> Bool)?
    ) {
        if key != snapshot.key {
            key = snapshot.key
        }
        if status != snapshot.status {
            status = snapshot.status
        }
        if isFetching != snapshot.isFetching {
            isFetching = snapshot.isFetching
        }
        switch (error, snapshot.error) {
        case (nil, nil): break
        case (_, let error): self.error = error
        }
        if updatedAt != snapshot.updatedAt {
            updatedAt = snapshot.updatedAt
        }
        if isStale != snapshot.isStale {
            isStale = snapshot.isStale
        }

        guard dataRevision != snapshot.dataRevision else { return }
        dataRevision = snapshot.dataRevision
        let selected = snapshot.data.map(select)
        if let data, let selected, areEqual?(data, selected) == true {
            return
        }
        if selected == nil, data == nil {
            return
        }
        data = selected
    }

    private func reset(key: QueryKey) {
        self.key = key
        data = nil
        error = nil
        status = .pending
        isFetching = false
        updatedAt = nil
        isStale = true
        dataRevision = 0
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
