import Foundation

extension QueryClient {
    public nonisolated func observe<Value: Sendable>(
        _ descriptor: Fetch<Value>
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
                if Task.isCancelled {
                    await self.removeObserver(id: observerID)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.removeObserver(id: observerID) }
            }
        }
    }

    public nonisolated func observe<Value: Codable & Sendable>(
        _ descriptor: Fetch<Value>
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
                if Task.isCancelled {
                    await self.removeObserver(id: observerID)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.removeObserver(id: observerID) }
            }
        }
    }

    func notifyObservers(for key: QueryKey, record: QueryRecord, now: Date) {
        for observer in observers[key]?.values ?? [:].values {
            observer.yield(record, now)
        }
    }

    static func status(for record: QueryRecord) -> QueryStatus {
        if record.value != nil {
            return .success
        }
        if record.error != nil {
            return .failure
        }
        return .pending
    }

    static func isStale(_ record: QueryRecord, now: Date) -> Bool {
        guard !record.invalidated else { return true }
        guard let updatedAt = record.updatedAt else { return true }
        return updatedAt.adding(record.options.staleTime) <= now
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

        observers[key, default: [:]][id] = QueryObserver { record, now in
            continuation.yield(Self.snapshot(key: key, record: record, now: now, as: Value.self))
        }
        observerKeys[id] = key

        continuation.yield(Self.snapshot(key: key, record: record, now: .now, as: Value.self))

        if record.value == nil || Self.isStale(record, now: .now) {
            Task {
                _ = try? await self.executeFetch(key: key, fetch: fetch)
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
        record.fetch = persistentFetch(
            key: key,
            storage: queryStorage(for: options),
            fetch: fetch
        )

        if record.value == nil, let stored: StoredQuery<Value> = try? await queryStorage(for: options)?.get(
            key: storageKey(for: key),
            as: StoredQuery<Value>.self
        ) {
            record.value = stored.value
            record.dataRevision &+= 1
            record.updatedAt = stored.updatedAt
            record.invalidated = stored.isInvalidated
        }

        record.observerCount += 1
        record.unusedAt = nil
        records[key] = record

        observers[key, default: [:]][id] = QueryObserver { record, now in
            continuation.yield(Self.snapshot(key: key, record: record, now: now, as: Value.self))
        }
        observerKeys[id] = key

        continuation.yield(Self.snapshot(key: key, record: record, now: .now, as: Value.self))

        if record.value == nil || Self.isStale(record, now: .now) {
            Task {
                _ = try? await self.executePersistentFetch(key: key, fetch: fetch)
            }
        }
    }

    private func removeObserver(id: UUID) {
        guard let key = observerKeys.removeValue(forKey: id),
              observers[key]?.removeValue(forKey: id) != nil else {
            return
        }
        if observers[key]?.isEmpty == true {
            observers[key] = nil
        }

        guard var record = records[key] else { return }
        record.observerCount = max(0, record.observerCount - 1)
        if record.observerCount == 0 {
            record.unusedAt = .now
        }
        records[key] = record
    }

    private static func snapshot<Value: Sendable>(
        key: QueryKey,
        record: QueryRecord,
        now: Date,
        as type: Value.Type
    ) -> QuerySnapshot<Value> {
        var snapshot = QuerySnapshot(
            key: key,
            status: status(for: record),
            isFetching: record.fetchTask != nil,
            data: record.value as? Value,
            error: record.error,
            updatedAt: record.updatedAt,
            isStale: isStale(record, now: now)
        )
        snapshot.dataRevision = record.dataRevision
        return snapshot
    }
}
