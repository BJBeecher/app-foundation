import Foundation

extension QueryClient {
    public func getQueryData<Value: Sendable>(
        key: QueryKey,
        as type: Value.Type = Value.self
    ) -> Value? {
        getMemoryQueryData(key: key, as: type)
    }

    public func getQueryData<Value: Codable & Sendable>(
        key: QueryKey,
        as type: Value.Type = Value.self
    ) async -> Value? {
        if let value: Value = getMemoryQueryData(key: key, as: type) {
            return value
        }

        let storage = records[key].map { queryStorage(for: $0.options) } ?? defaultStorage
        guard let stored: StoredQuery<Value> = try? await storage?.get(
            key: storageKey(for: key),
            as: StoredQuery<Value>.self
        ) else {
            return nil
        }

        var record = records[key] ?? QueryRecord(options: defaultFetchOptions)
        record.value = stored.value
        record.dataRevision &+= 1
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
        await persist(value, key: key, updatedAt: updatedAt)
    }

    public func updateQueryData<Value: Sendable>(
        key: QueryKey,
        as type: Value.Type = Value.self,
        _ update: @Sendable (inout Value) -> Void
    ) {
        guard var value: Value = getQueryData(key: key, as: type) else { return }
        let original = value
        update(&value)
        guard !queryValuesEqual(original, value) else { return }
        setQueryData(key: key, value)
    }

    public func updateQueryData<Value: Codable & Sendable>(
        key: QueryKey,
        as type: Value.Type = Value.self,
        _ update: @Sendable (inout Value) -> Void
    ) async {
        guard var value: Value = await getQueryData(key: key, as: type) else { return }
        let original = value
        update(&value)
        guard !queryValuesEqual(original, value) else { return }
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
            cancelPendingPersistence(for: key)
            record.invalidated = true
            records[key] = record
            notifyObservers(for: key, record: record, now: .now)
            try? await queryStorage(for: record.options)?.delete(key: storageKey(for: key))
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
            guard let record = records[key] else { continue }
            let storage = queryStorage(for: record.options)
            removeRecord(for: key, existingRecord: record)
            try? await storage?.delete(key: storageKey(for: key))
        }
    }

    public func clear() async {
        let existingRecords = records
        let keys = Array(existingRecords.keys)
        for key in keys {
            guard let existingRecord = existingRecords[key] else { continue }
            removeRecord(for: key, existingRecord: existingRecord)
        }
        for key in keys {
            let storage = existingRecords[key].map { queryStorage(for: $0.options) } ?? defaultStorage
            try? await storage?.delete(key: storageKey(for: key))
        }
    }

    func getMemoryQueryData<Value: Sendable>(
        key: QueryKey,
        as type: Value.Type = Value.self
    ) -> Value? {
        pruneExpiredRecords(now: .now)
        return records[key]?.value as? Value
    }

    func setMemoryQueryData<Value: Sendable>(
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
        if !queryValuesEqual(record.value, value) {
            record.value = value
            record.dataRevision &+= 1
        }
        record.error = nil
        record.updatedAt = updatedAt
        record.invalidated = false
        records[key] = record
        notifyObservers(for: key, record: record, now: updatedAt)
    }

    func removeRecord(for key: QueryKey, existingRecord: QueryRecord) {
        existingRecord.fetchTask?.cancel()
        cancelPendingPersistence(for: key)
        persistenceRevisions[key] = nil

        let observerCount = observers[key]?.count ?? 0
        guard observerCount > 0 else {
            records[key] = nil
            return
        }

        var emptyRecord = QueryRecord(options: existingRecord.options)
        emptyRecord.fetch = existingRecord.fetch
        emptyRecord.observerCount = observerCount
        records[key] = emptyRecord
        notifyObservers(for: key, record: emptyRecord, now: .now)
    }

    func pruneExpiredRecords(now: Date) {
        let expiredKeys = records.compactMap { key, record -> QueryKey? in
            guard record.observerCount == 0,
                  record.fetchTask == nil,
                  let unusedAt = record.unusedAt,
                  let garbageCollectionTime = record.options.garbageCollectionTime,
                  unusedAt.adding(garbageCollectionTime) <= now else {
                return nil
            }
            return key
        }

        for key in expiredKeys {
            cancelPendingPersistence(for: key)
            persistenceRevisions[key] = nil
            records[key] = nil
        }
    }

    private func matches(
        _ filter: QueryFilter,
        key: QueryKey,
        record: QueryRecord,
        now: Date
    ) -> Bool {
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
            status: Self.status(for: record),
            isFetching: record.fetchTask != nil,
            updatedAt: record.updatedAt,
            isActive: record.observerCount > 0,
            isStale: Self.isStale(record, now: now)
        )
    }
}

func queryValuesEqual(_ lhs: (any Sendable)?, _ rhs: any Sendable) -> Bool {
    guard let lhs = lhs as? any Equatable else { return false }
    return lhs.isEqual(to: rhs)
}

private extension Equatable {
    func isEqual(to other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

extension Date {
    func adding(_ duration: Duration) -> Date {
        let components = duration.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return addingTimeInterval(seconds + attoseconds)
    }
}
