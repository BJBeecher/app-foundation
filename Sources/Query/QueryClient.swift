import Foundation

private struct AnyQueryValue: @unchecked Sendable {
    let value: Any
}

private struct QueryRecord {
    var value: Any?
    var error: Error?
    var updatedAt: Date?
    var invalidated = false
    var fetchTask: Task<AnyQueryValue, Error>?
    var observerCount = 0
    var unusedAt: Date?
    var options: FetchOptions
    var fetch: (@Sendable () async throws -> AnyQueryValue)?

    init(options: FetchOptions) {
        self.options = options
    }
}

private struct QueryObserver {
    let key: QueryKey
    let yield: @Sendable (QueryRecord, Date) -> Void
}

public actor QueryClient {
    public static let shared = QueryClient()

    private var records: [QueryKey: QueryRecord] = [:]
    private var observers: [UUID: QueryObserver] = [:]
    private let defaultFetchOptions: FetchOptions
    private nonisolated let defaultMutationOptions: MutationDefaultOptions
    private let storage: QueryStorage?

    public init(
        defaultFetchOptions: FetchOptions = FetchOptions(),
        defaultMutationOptions: MutationDefaultOptions = MutationDefaultOptions()
    ) {
        self.defaultFetchOptions = defaultFetchOptions
        self.defaultMutationOptions = defaultMutationOptions
        self.storage = defaultFetchOptions.storage
    }

    public nonisolated func createMutation<Variables: Sendable, Value: Sendable>(
        _ options: MutationOptions<Variables, Value>
    ) -> Mutation<Variables, Value> {
        Mutation(
            defaultOptions: defaultMutationOptions,
            options: options
        )
    }

    private func storageKey(for key: QueryKey) -> String {
        guard let data = try? JSONEncoder().encode(key) else {
            return key.description
        }

        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    public func fetch<Value: Sendable>(_ descriptor: Fetch<Value>) async throws -> Value {
        let options = descriptor.options ?? defaultFetchOptions
        pruneExpiredRecords(now: .now)

        var record = records[descriptor.key] ?? QueryRecord(options: options)
        record.options = options
        record.fetch = { AnyQueryValue(value: try await descriptor.operation()) }

        if let value = record.value as? Value, !isStale(record, now: .now) {
            records[descriptor.key] = record
            return value
        }

        records[descriptor.key] = record
        return try await executeFetch(
            key: descriptor.key,
            options: options,
            fetch: descriptor.operation
        )
    }

    public func fetch<Value: Codable & Sendable>(_ descriptor: Fetch<Value>) async throws -> Value {
        let options = descriptor.options ?? defaultFetchOptions
        pruneExpiredRecords(now: .now)

        var record = records[descriptor.key] ?? QueryRecord(options: options)
        record.options = options
        record.fetch = persistentFetch(key: descriptor.key, fetch: descriptor.operation)

        if let value = record.value as? Value, !isStale(record, now: .now) {
            records[descriptor.key] = record
            return value
        }

        if record.value == nil, let stored: StoredQuery<Value> = try? await storage?.get(
            key: storageKey(for: descriptor.key),
            as: StoredQuery<Value>.self
        ) {
            record.value = stored.value
            record.updatedAt = stored.updatedAt
            record.invalidated = stored.isInvalidated

            if !isStale(record, now: .now) {
                records[descriptor.key] = record
                return stored.value
            }
        }

        records[descriptor.key] = record
        return try await executePersistentFetch(
            key: descriptor.key,
            options: options,
            fetch: descriptor.operation
        )
    }

    public func prefetch<Value: Sendable>(_ descriptor: Fetch<Value>) async {
        _ = try? await fetch(descriptor)
    }

    public func prefetch<Value: Codable & Sendable>(_ descriptor: Fetch<Value>) async {
        _ = try? await fetch(descriptor)
    }

    public func getQueryData<Value: Sendable>(key: QueryKey, as type: Value.Type = Value.self) -> Value? {
        getMemoryQueryData(key: key, as: type)
    }

    public func getQueryData<Value: Codable & Sendable>(
        key: QueryKey,
        as type: Value.Type = Value.self
    ) async -> Value? {
        if let value: Value = getMemoryQueryData(key: key, as: type) {
            return value
        }

        guard let stored: StoredQuery<Value> = try? await storage?.get(
            key: storageKey(for: key),
            as: StoredQuery<Value>.self
        ) else {
            return nil
        }

        var record = records[key] ?? QueryRecord(options: defaultFetchOptions)
        record.value = stored.value
        record.updatedAt = stored.updatedAt
        record.invalidated = stored.isInvalidated
        records[key] = record

        return stored.value
    }

    public func setQueryData<Value: Sendable>(
        key: QueryKey,
        _ value: Value,
        options: FetchOptions? = nil,
        updatedAt: Date = .now
    ) {
        setMemoryQueryData(key: key, value, options: options, updatedAt: updatedAt)
    }

    public func setQueryData<Value: Codable & Sendable>(
        key: QueryKey,
        _ value: Value,
        options: FetchOptions? = nil,
        updatedAt: Date = .now
    ) async {
        setMemoryQueryData(key: key, value, options: options, updatedAt: updatedAt)
        try? await storage?.save(StoredQuery(value: value, updatedAt: updatedAt), key: storageKey(for: key))
    }

    public func updateQueryData<Value: Sendable>(
        key: QueryKey,
        as type: Value.Type = Value.self,
        _ update: @Sendable (inout Value) -> Void
    ) {
        guard var value: Value = getQueryData(key: key, as: type) else { return }
        update(&value)
        setQueryData(key: key, value)
    }

    public func updateQueryData<Value: Codable & Sendable>(
        key: QueryKey,
        as type: Value.Type = Value.self,
        _ update: @Sendable (inout Value) -> Void
    ) async {
        guard var value: Value = await getQueryData(key: key, as: type) else { return }
        update(&value)
        await setQueryData(key: key, value)
    }

    public func invalidateQueries(
        matching filter: QueryFilter = .all,
        refetch: QueryRefetchBehavior = .active
    ) async {
        pruneExpiredRecords(now: .now)

        let keys = records.keys.filter { key in
            guard let record = records[key] else { return false }
            return matches(filter, key: key, record: record, now: .now)
        }

        for key in keys {
            guard var record = records[key] else { continue }
            record.invalidated = true
            records[key] = record
            try? await storage?.delete(key: storageKey(for: key))
            notifyObservers(for: key, record: record, now: .now)
        }

        guard refetch != .none else { return }

        for key in keys {
            guard let record = records[key],
                  refetch == .all || record.observerCount > 0,
                  let fetch = record.fetch else {
                continue
            }

            Task {
                _ = try? await self.executeStoredFetch(key: key, fetch: fetch)
            }
        }
    }

    public func removeQueries(matching filter: QueryFilter = .all) async {
        pruneExpiredRecords(now: .now)
        let keys = records.keys.filter { key in
            guard let record = records[key] else { return false }
            return matches(filter, key: key, record: record, now: .now)
        }

        for key in keys {
            records[key] = nil
            try? await storage?.delete(key: storageKey(for: key))
            notifyObservers(for: key, record: QueryRecord(options: defaultFetchOptions), now: .now)
        }
    }

    public func clear() async {
        let keys = Array(records.keys)
        records.removeAll()
        observers.removeAll()
        for key in keys {
            try? await storage?.delete(key: storageKey(for: key))
        }
    }

    nonisolated func snapshots<Value: Sendable>(
        for descriptor: Fetch<Value>
    ) -> AsyncStream<QuerySnapshot<Value>> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observerID = UUID()
            let task = Task {
                await self.addObserver(
                    id: observerID,
                    key: descriptor.key,
                    options: descriptor.options,
                    continuation: continuation,
                    fetch: descriptor.operation
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.removeObserver(id: observerID) }
            }
        }
    }

    nonisolated func persistentSnapshots<Value: Codable & Sendable>(
        for descriptor: Fetch<Value>
    ) -> AsyncStream<QuerySnapshot<Value>> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observerID = UUID()
            let task = Task {
                await self.addPersistentObserver(
                    id: observerID,
                    key: descriptor.key,
                    options: descriptor.options,
                    continuation: continuation,
                    fetch: descriptor.operation
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.removeObserver(id: observerID) }
            }
        }
    }

    private func addObserver<Value: Sendable>(
        id: UUID,
        key: QueryKey,
        options: FetchOptions?,
        continuation: AsyncStream<QuerySnapshot<Value>>.Continuation,
        fetch: @escaping @Sendable () async throws -> Value
    ) {
        pruneExpiredRecords(now: .now)

        let options = options ?? defaultFetchOptions
        var record = records[key] ?? QueryRecord(options: options)
        record.options = options
        record.fetch = { AnyQueryValue(value: try await fetch()) }
        record.observerCount += 1
        record.unusedAt = nil
        records[key] = record

        observers[id] = QueryObserver(key: key) { record, now in
            continuation.yield(Self.snapshot(key: key, record: record, now: now, as: Value.self))
        }

        continuation.yield(Self.snapshot(key: key, record: record, now: .now, as: Value.self))

        if record.value == nil || isStale(record, now: .now) {
            Task {
                _ = try? await self.executeFetch(key: key, options: options, fetch: fetch)
            }
        }
    }

    private func addPersistentObserver<Value: Codable & Sendable>(
        id: UUID,
        key: QueryKey,
        options: FetchOptions?,
        continuation: AsyncStream<QuerySnapshot<Value>>.Continuation,
        fetch: @escaping @Sendable () async throws -> Value
    ) async {
        pruneExpiredRecords(now: .now)

        let options = options ?? defaultFetchOptions
        var record = records[key] ?? QueryRecord(options: options)
        record.options = options
        record.fetch = persistentFetch(key: key, fetch: fetch)

        if record.value == nil, let stored: StoredQuery<Value> = try? await storage?.get(
            key: storageKey(for: key),
            as: StoredQuery<Value>.self
        ) {
            record.value = stored.value
            record.updatedAt = stored.updatedAt
            record.invalidated = stored.isInvalidated
        }

        record.observerCount += 1
        record.unusedAt = nil
        records[key] = record

        observers[id] = QueryObserver(key: key) { record, now in
            continuation.yield(Self.snapshot(key: key, record: record, now: now, as: Value.self))
        }

        continuation.yield(Self.snapshot(key: key, record: record, now: .now, as: Value.self))

        if record.value == nil || isStale(record, now: .now) {
            Task {
                _ = try? await self.executePersistentFetch(key: key, options: options, fetch: fetch)
            }
        }
    }

    private func removeObserver(id: UUID) {
        guard let observer = observers[id] else { return }
        observers[id] = nil

        guard var record = records[observer.key] else { return }
        record.observerCount = max(0, record.observerCount - 1)
        if record.observerCount == 0 {
            record.unusedAt = .now
        }
        records[observer.key] = record
    }

    private func getMemoryQueryData<Value: Sendable>(key: QueryKey, as type: Value.Type = Value.self) -> Value? {
        pruneExpiredRecords(now: .now)
        return records[key]?.value as? Value
    }

    private func setMemoryQueryData<Value: Sendable>(
        key: QueryKey,
        _ value: Value,
        options: FetchOptions? = nil,
        updatedAt: Date = .now
    ) {
        pruneExpiredRecords(now: updatedAt)

        var record = records[key] ?? QueryRecord(options: options ?? defaultFetchOptions)
        if let options {
            record.options = options
        }
        record.value = value
        record.error = nil
        record.updatedAt = updatedAt
        record.invalidated = false
        records[key] = record
        notifyObservers(for: key, record: record, now: updatedAt)
    }

    private func executeStoredFetch(key: QueryKey, fetch: @escaping @Sendable () async throws -> AnyQueryValue) async throws -> Any {
        let options = records[key]?.options ?? defaultFetchOptions

        if let existingTask = records[key]?.fetchTask {
            return try await existingTask.value.value
        }

        let task = Task<AnyQueryValue, Error> {
            try await Self.runWithRetry(options: options, fetch: fetch)
        }

        var record = records[key] ?? QueryRecord(options: options)
        record.options = options
        record.fetchTask = task
        records[key] = record
        notifyObservers(for: key, record: record, now: .now)

        do {
            let payload = try await task.value
            var record = records[key] ?? QueryRecord(options: options)
            record.options = options
            record.value = payload.value
            record.error = nil
            record.updatedAt = .now
            record.invalidated = false
            record.fetchTask = nil
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)
            return payload.value
        } catch {
            var record = records[key] ?? QueryRecord(options: options)
            record.error = error
            record.fetchTask = nil
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)
            throw error
        }
    }

    private func persistentFetch<Value: Codable & Sendable>(
        key: QueryKey,
        fetch: @escaping @Sendable () async throws -> Value
    ) -> @Sendable () async throws -> AnyQueryValue {
        let storage = storage
        let storageKey = storageKey(for: key)
        return {
            let value = try await fetch()
            try? await storage?.save(StoredQuery(value: value, updatedAt: .now), key: storageKey)
            return AnyQueryValue(value: value)
        }
    }

    private func executeFetch<Value: Sendable>(
        key: QueryKey,
        options: FetchOptions,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let existingTask = records[key]?.fetchTask {
            let payload = try await existingTask.value
            guard let value = payload.value as? Value else {
                throw QueryClientError.typeMismatch(key)
            }
            return value
        }

        let task = Task<AnyQueryValue, Error> {
            AnyQueryValue(value: try await Self.runWithRetry(options: options, fetch: fetch))
        }

        var record = records[key] ?? QueryRecord(options: options)
        record.options = options
        record.fetchTask = task
        records[key] = record
        notifyObservers(for: key, record: record, now: .now)

        do {
            let payload = try await task.value
            guard let value = payload.value as? Value else {
                throw QueryClientError.typeMismatch(key)
            }

            var record = records[key] ?? QueryRecord(options: options)
            record.options = options
            record.value = value
            record.error = nil
            record.updatedAt = .now
            record.invalidated = false
            record.fetchTask = nil
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)

            return value
        } catch {
            var record = records[key] ?? QueryRecord(options: options)
            record.error = error
            record.fetchTask = nil
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)
            throw error
        }
    }

    private func executePersistentFetch<Value: Codable & Sendable>(
        key: QueryKey,
        options: FetchOptions,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let existingTask = records[key]?.fetchTask {
            let payload = try await existingTask.value
            guard let value = payload.value as? Value else {
                throw QueryClientError.typeMismatch(key)
            }
            return value
        }

        let storage = storage
        let storageKey = storageKey(for: key)
        let task = Task<AnyQueryValue, Error> {
            let value = try await Self.runWithRetry(options: options, fetch: fetch)
            try? await storage?.save(StoredQuery(value: value, updatedAt: .now), key: storageKey)
            return AnyQueryValue(value: value)
        }

        var record = records[key] ?? QueryRecord(options: options)
        record.options = options
        record.fetchTask = task
        records[key] = record
        notifyObservers(for: key, record: record, now: .now)

        do {
            let payload = try await task.value
            guard let value = payload.value as? Value else {
                throw QueryClientError.typeMismatch(key)
            }

            var record = records[key] ?? QueryRecord(options: options)
            record.options = options
            record.value = value
            record.error = nil
            record.updatedAt = .now
            record.invalidated = false
            record.fetchTask = nil
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)

            return value
        } catch {
            var record = records[key] ?? QueryRecord(options: options)
            record.error = error
            record.fetchTask = nil
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)
            throw error
        }
    }

    private static func runWithRetry<Value>(
        options: FetchOptions,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        var failureCount = 0

        while true {
            do {
                return try await fetch()
            } catch {
                guard options.retry.shouldRetry(afterFailureCount: failureCount) else {
                    throw error
                }

                failureCount += 1
                try await Task.sleep(for: options.retryDelay.duration(forAttempt: failureCount, error: error))
            }
        }
    }

    private func notifyObservers(for key: QueryKey, record: QueryRecord, now: Date) {
        for observer in observers.values where observer.key == key {
            observer.yield(record, now)
        }
    }

    private func matches(_ filter: QueryFilter, key: QueryKey, record: QueryRecord, now: Date) -> Bool {
        if let filterKey = filter.key {
            if filter.exact {
                guard key == filterKey else { return false }
            } else {
                guard key.starts(with: filterKey) else { return false }
            }
        }

        if let predicate = filter.predicate {
            return predicate(queryInfo(for: key, record: record, now: now))
        }

        return true
    }

    private func queryInfo(for key: QueryKey, record: QueryRecord, now: Date) -> QueryInfo {
        QueryInfo(
            key: key,
            status: status(for: record),
            isFetching: record.fetchTask != nil,
            updatedAt: record.updatedAt,
            isActive: record.observerCount > 0,
            isStale: isStale(record, now: now)
        )
    }

    private func isStale(_ record: QueryRecord, now: Date) -> Bool {
        guard !record.invalidated else { return true }
        guard let updatedAt = record.updatedAt else { return true }
        return updatedAt.adding(record.options.staleTime) <= now
    }

    private static func snapshot<Value: Sendable>(
        key: QueryKey,
        record: QueryRecord,
        now: Date,
        as type: Value.Type
    ) -> QuerySnapshot<Value> {
        QuerySnapshot(
            key: key,
            status: status(for: record),
            isFetching: record.fetchTask != nil,
            data: record.value as? Value,
            error: record.error,
            updatedAt: record.updatedAt,
            isStale: isStale(record, now: now)
        )
    }

    private func status(for record: QueryRecord) -> QueryStatus {
        Self.status(for: record)
    }

    private static func status(for record: QueryRecord) -> QueryStatus {
        if record.value != nil {
            return .success
        }

        if record.error != nil {
            return .failure
        }

        return .pending
    }

    private static func isStale(_ record: QueryRecord, now: Date) -> Bool {
        guard !record.invalidated else { return true }
        guard let updatedAt = record.updatedAt else { return true }
        return updatedAt.adding(record.options.staleTime) <= now
    }

    private func pruneExpiredRecords(now: Date) {
        records = records.filter { _, record in
            guard record.observerCount == 0,
                  let unusedAt = record.unusedAt,
                  let garbageCollectionTime = record.options.garbageCollectionTime else {
                return true
            }
            return unusedAt.adding(garbageCollectionTime) > now
        }
    }
}

public enum QueryClientError: Error, Sendable, Equatable {
    case typeMismatch(QueryKey)
}

private extension Date {
    func adding(_ duration: Duration) -> Date {
        let components = duration.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return addingTimeInterval(seconds + attoseconds)
    }
}
