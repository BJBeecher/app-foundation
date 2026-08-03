import Foundation

extension QueryClient {
    func storageKey(for key: QueryKey) -> String {
        guard let data = try? JSONEncoder().encode(key) else {
            return key.description
        }

        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    func queryStorage(for options: FetchOptions) -> QueryStorage? {
        options.storage ?? defaultStorage
    }

    func persist<Value: Codable & Sendable>(
        _ value: Value,
        key: QueryKey,
        updatedAt: Date
    ) async {
        guard let storage = records[key].map({ queryStorage(for: $0.options) }) ?? defaultStorage else {
            return
        }

        switch records[key]?.options.persistence ?? defaultFetchOptions.persistence ?? .immediate {
        case .immediate:
            cancelPendingPersistence(for: key)
            try? await storage.save(
                StoredQuery(value: value, updatedAt: updatedAt),
                key: storageKey(for: key)
            )
        case let .debounced(duration):
            cancelPendingPersistence(for: key)
            let revision = persistenceRevisions[key, default: 0]
            persistenceTasks[key] = Task {
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                await self.persistIfCurrent(
                    value,
                    key: key,
                    updatedAt: updatedAt,
                    revision: revision
                )
            }
        }
    }

    func cancelPendingPersistence(for key: QueryKey) {
        persistenceTasks[key]?.cancel()
        persistenceTasks[key] = nil
        persistenceRevisions[key, default: 0] &+= 1
    }

    private func persistIfCurrent<Value: Codable & Sendable>(
        _ value: Value,
        key: QueryKey,
        updatedAt: Date,
        revision: UInt64
    ) async {
        guard persistenceRevisions[key] == revision,
              let record = records[key],
              !record.invalidated else {
            return
        }
        let storage = queryStorage(for: record.options)
        try? await storage?.save(
            StoredQuery(value: value, updatedAt: updatedAt),
            key: storageKey(for: key)
        )
        if persistenceRevisions[key] == revision {
            persistenceTasks[key] = nil
        }
    }
}
