import Foundation

extension QueryClient {
    public func fetch<Value: Sendable>(_ descriptor: Fetch<Value>) async throws -> Value {
        let options = descriptor.options ?? defaultFetchOptions
        pruneExpiredRecords(now: .now)

        var record = records[descriptor.key] ?? QueryRecord(options: options)
        record.options = options
        record.fetch = { AnyQueryValue(value: try await descriptor.operation()) }

        if let value = record.value as? Value, !Self.isStale(record, now: .now) {
            records[descriptor.key] = record
            return value
        }

        records[descriptor.key] = record
        return try await executeFetch(
            key: descriptor.key,
            fetch: descriptor.operation
        )
    }

    public func fetch<Value: Codable & Sendable>(_ descriptor: Fetch<Value>) async throws -> Value {
        let options = descriptor.options ?? defaultFetchOptions
        pruneExpiredRecords(now: .now)

        var record = records[descriptor.key] ?? QueryRecord(options: options)
        record.options = options
        record.fetch = persistentFetch(
            key: descriptor.key,
            storage: queryStorage(for: options),
            fetch: descriptor.operation
        )

        if let value = record.value as? Value, !Self.isStale(record, now: .now) {
            records[descriptor.key] = record
            return value
        }

        if record.value == nil, let stored: StoredQuery<Value> = try? await queryStorage(for: options)?.get(
            key: storageKey(for: descriptor.key),
            as: StoredQuery<Value>.self
        ) {
            record.value = stored.value
            record.dataRevision &+= 1
            record.updatedAt = stored.updatedAt
            record.invalidated = stored.isInvalidated

            if !Self.isStale(record, now: .now) {
                records[descriptor.key] = record
                return stored.value
            }
        }

        records[descriptor.key] = record
        return try await executePersistentFetch(
            key: descriptor.key,
            fetch: descriptor.operation
        )
    }

    public func prefetch<Value: Sendable>(_ descriptor: Fetch<Value>) async {
        _ = try? await fetch(descriptor)
    }

    public func prefetch<Value: Codable & Sendable>(_ descriptor: Fetch<Value>) async {
        _ = try? await fetch(descriptor)
    }

    func executeStoredFetch(
        key: QueryKey,
        fetch: @escaping @Sendable () async throws -> AnyQueryValue
    ) async throws -> any Sendable {
        let options = records[key]?.options ?? defaultFetchOptions

        if let existingTask = records[key]?.fetchTask {
            return try await existingTask.value.value
        }

        let task = Task<AnyQueryValue, Error> {
            try await Self.runWithRetry(options: options, fetch: fetch)
        }
        let fetchID = UUID()

        var record = records[key] ?? QueryRecord(options: options)
        record.options = options
        record.fetchTask = task
        record.fetchID = fetchID
        records[key] = record
        notifyObservers(for: key, record: record, now: .now)

        do {
            let payload = try await task.value
            guard var record = records[key], record.fetchID == fetchID else {
                return payload.value
            }
            record.options = options
            if !queryValuesEqual(record.value, payload.value) {
                record.value = payload.value
                record.dataRevision &+= 1
            }
            record.error = nil
            record.updatedAt = .now
            record.invalidated = false
            record.fetchTask = nil
            record.fetchID = nil
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)
            return payload.value
        } catch {
            guard var record = records[key], record.fetchID == fetchID else {
                throw error
            }
            record.error = error
            record.fetchTask = nil
            record.fetchID = nil
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)
            throw error
        }
    }

    func persistentFetch<Value: Codable & Sendable>(
        key: QueryKey,
        storage: QueryStorage?,
        fetch: @escaping @Sendable () async throws -> Value
    ) -> @Sendable () async throws -> AnyQueryValue {
        let storageKey = storageKey(for: key)
        return {
            let value = try await fetch()
            try? await storage?.save(StoredQuery(value: value, updatedAt: .now), key: storageKey)
            return AnyQueryValue(value: value)
        }
    }

    func executeFetch<Value: Sendable>(
        key: QueryKey,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let value = try await executeStoredFetch(key: key) {
            AnyQueryValue(value: try await fetch())
        }
        guard let value = value as? Value else {
            throw QueryClientError.typeMismatch(key)
        }
        return value
    }

    func executePersistentFetch<Value: Codable & Sendable>(
        key: QueryKey,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let value = try await executeStoredFetch(
            key: key,
            fetch: persistentFetch(
                key: key,
                storage: records[key].map { queryStorage(for: $0.options) } ?? defaultStorage,
                fetch: fetch
            )
        )
        guard let value = value as? Value else {
            throw QueryClientError.typeMismatch(key)
        }
        return value
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
                try await Task.sleep(
                    for: options.retryDelay.duration(forAttempt: failureCount, error: error)
                )
            }
        }
    }
}
