import Foundation
import Testing
@testable import VLQuery

private actor QueryCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

private enum QueryTestError: Error {
    case failed
}

private actor TestQueryStorage: QueryStorage {
    private var values: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var saveCount = 0

    func get<Value: Codable & Sendable>(key: String, as type: Value.Type) async throws -> Value? {
        guard let data = values[key] else { return nil }
        return try decoder.decode(Value.self, from: data)
    }

    func save<Value: Codable & Sendable>(_ value: Value, key: String) async throws {
        saveCount += 1
        values[key] = try encoder.encode(value)
    }

    func delete(key: String) async throws {
        values[key] = nil
    }
}

private struct RevisionValue: Codable, Equatable, Sendable {
    var count: Int
}

@Test
func testFetchDeduplicatesConcurrentFetchesForTheSameKey() async throws {
    let client = QueryClient(defaultFetchOptions: FetchOptions(staleTime: .seconds(60), retry: .never))
    let counter = QueryCounter()
    let userFetch = Fetch(key: ["user", 1]) {
        try await Task.sleep(for: .milliseconds(50))
        return await counter.next()
    }

    let values = try await withThrowingTaskGroup(of: Int.self, returning: [Int].self) { group in
        for _ in 0..<8 {
            group.addTask {
                try await client.fetch(userFetch)
            }
        }

        var values: [Int] = []
        for try await value in group {
            values.append(value)
        }
        return values
    }

    #expect(values.count == 8)
    #expect(values.allSatisfy { $0 == 1 })
    #expect(await counter.value == 1)
}

@Test
func testFetchReturnsFreshCachedData() async throws {
    let client = QueryClient(defaultFetchOptions: FetchOptions(staleTime: .seconds(60), retry: .never))
    let counter = QueryCounter()
    let feedFetch = Fetch(key: ["feed"]) {
        await counter.next()
    }

    let first = try await client.fetch(feedFetch)
    let second = try await client.fetch(feedFetch)

    #expect(first == 1)
    #expect(second == 1)
    #expect(await counter.value == 1)
}

@Test
func testInvalidatingQueriesMarksMatchingPrefixStale() async throws {
    let client = QueryClient(defaultFetchOptions: FetchOptions(staleTime: .seconds(60), retry: .never))
    let counter = QueryCounter()
    let postsFetch = Fetch(key: ["posts", 1]) {
        await counter.next()
    }

    let first = try await client.fetch(postsFetch)

    await client.invalidateQueries(matching: QueryFilter(key: ["posts"], exact: false), refetch: .none)

    let second = try await client.fetch(postsFetch)

    #expect(first == 1)
    #expect(second == 2)
    #expect(await counter.value == 2)
}

@Test
func testSetAndUpdateQueryData() async throws {
    let client = QueryClient(defaultFetchOptions: FetchOptions(retry: .never))

    await client.setQueryData(key: ["settings"], ["theme": "light"])
    await client.updateQueryData(key: ["settings"], as: [String: String].self) { settings in
        settings["theme"] = "dark"
    }

    let settings: [String: String]? = await client.getQueryData(key: ["settings"])
    #expect(settings?["theme"] == "dark")
}

@Test
func testSetAndUpdateQueryDataPersistsWhenStorageIsConfigured() async throws {
    let storage = TestQueryStorage()
    let options = FetchOptions(
        retry: .never,
        storage: storage
    )
    let firstClient = QueryClient(defaultFetchOptions: options)
    let secondClient = QueryClient(defaultFetchOptions: options)

    await firstClient.setQueryData(key: ["persisted-settings"], ["theme": "light"])
    await firstClient.updateQueryData(key: ["persisted-settings"], as: [String: String].self) { settings in
        settings["theme"] = "dark"
    }

    let settings: [String: String]? = await secondClient.getQueryData(key: ["persisted-settings"])
    #expect(settings?["theme"] == "dark")
}

@Test
func testEqualQueryDataDoesNotAdvanceDataRevision() async throws {
    let client = QueryClient(defaultFetchOptions: FetchOptions(staleTime: .seconds(60), retry: .never))
    let fetch = Fetch(key: ["revision"]) {
        RevisionValue(count: 1)
    }
    var snapshots = client.observe(fetch).makeAsyncIterator()

    var initial = await snapshots.next()
    while initial?.data == nil {
        initial = await snapshots.next()
    }

    await client.setQueryData(key: fetch.key, RevisionValue(count: 1))
    var currentSnapshots = client.observe(fetch).makeAsyncIterator()
    let equalUpdate = await currentSnapshots.next()

    #expect(equalUpdate?.dataRevision == initial?.dataRevision)
}

@Test
func testDebouncedPersistenceWritesOnlyTheLatestValue() async throws {
    let storage = TestQueryStorage()
    let options = FetchOptions(
        staleTime: .seconds(60),
        retry: .never,
        storage: storage,
        persistence: .debounced(.milliseconds(20))
    )
    let client = QueryClient(defaultFetchOptions: options)

    await client.setQueryData(key: ["debounced"], RevisionValue(count: 1))
    await client.setQueryData(key: ["debounced"], RevisionValue(count: 2))
    try await Task.sleep(for: .milliseconds(100))

    let hydratedClient = QueryClient(defaultFetchOptions: options)
    let value: RevisionValue? = await hydratedClient.getQueryData(key: ["debounced"])
    #expect(value == RevisionValue(count: 2))
    #expect(await storage.saveCount == 1)
}

@Test
func testInvalidationCancelsDebouncedPersistence() async throws {
    let storage = TestQueryStorage()
    let options = FetchOptions(
        retry: .never,
        storage: storage,
        persistence: .debounced(.milliseconds(100))
    )
    let client = QueryClient(defaultFetchOptions: options)

    await client.setQueryData(key: ["cancelled-persistence"], RevisionValue(count: 1))
    await client.invalidateQueries(
        matching: QueryFilter(key: ["cancelled-persistence"], exact: true),
        refetch: .none
    )
    try await Task.sleep(for: .milliseconds(150))

    #expect(await storage.saveCount == 0)
}

@Test
func testClearKeepsActiveObserversConnected() async throws {
    let client = QueryClient(
        defaultFetchOptions: FetchOptions(staleTime: .seconds(60), retry: .never)
    )
    let fetch = Fetch(key: ["clear-observer"]) { RevisionValue(count: 1) }
    var snapshots = client.observe(fetch).makeAsyncIterator()

    var snapshot = await snapshots.next()
    while snapshot?.data == nil {
        snapshot = await snapshots.next()
    }

    await client.clear()
    let cleared = await snapshots.next()
    await client.setQueryData(key: fetch.key, RevisionValue(count: 2))
    let updated = await snapshots.next()

    #expect(cleared?.status == .pending)
    #expect(cleared?.data == nil)
    #expect(updated?.data == RevisionValue(count: 2))
}

@Test
func testRemovedInFlightQueryCannotRestoreItsCacheRecord() async throws {
    let client = QueryClient(defaultFetchOptions: FetchOptions(retry: .never))
    let key: QueryKey = ["removed-in-flight"]
    let fetchTask = Task {
        try? await client.fetch(Fetch(key: key) {
            try await Task.sleep(for: .seconds(1))
            return RevisionValue(count: 1)
        })
    }

    try await Task.sleep(for: .milliseconds(20))
    await client.removeQueries(matching: QueryFilter(key: key, exact: true))
    _ = await fetchTask.value

    let value: RevisionValue? = await client.getQueryData(key: key)
    #expect(value == nil)
}

@Test
func testRetryPolicyRetriesUntilSuccess() async throws {
    let client = QueryClient(
        defaultFetchOptions: FetchOptions(
            retry: .maxAttempts(2),
            retryDelay: .constant(.zero)
        )
    )
    let counter = QueryCounter()

    let value = try await client.fetch(Fetch(key: ["retry"]) {
        let attempt = await counter.next()
        if attempt < 3 {
            throw QueryTestError.failed
        }
        return attempt
    })

    #expect(value == 3)
    #expect(await counter.value == 3)
}

@Test
func testQueryHydratesFromStorageWhenStorageIsConfigured() async throws {
    let storage = TestQueryStorage()
    let options = FetchOptions(
        staleTime: .seconds(60),
        retry: .never,
        storage: storage
    )
    let firstClient = QueryClient(defaultFetchOptions: options)
    let secondClient = QueryClient(defaultFetchOptions: options)
    let counter = QueryCounter()
    let persistedFetch = Fetch(key: ["persisted"]) {
        await counter.next()
    }

    let first = try await firstClient.fetch(persistedFetch)
    let second = try await secondClient.fetch(persistedFetch)

    #expect(first == 1)
    #expect(second == 1)
    #expect(await counter.value == 1)
}

@Test
func testQueryUsesDescriptorStorageOverride() async throws {
    let storage = TestQueryStorage()
    let counter = QueryCounter()
    let fetch = Fetch(
        key: ["descriptor-storage"],
        options: FetchOptions(
            staleTime: .seconds(60),
            retry: .never,
            storage: storage
        )
    ) {
        await counter.next()
    }

    let first = try await QueryClient().fetch(fetch)
    let second = try await QueryClient().fetch(fetch)

    #expect(first == 1)
    #expect(second == 1)
    #expect(await counter.value == 1)
}

@Test
func testInvalidationRefetchesHydratedStorageData() async throws {
    let storage = TestQueryStorage()
    let options = FetchOptions(
        staleTime: .seconds(60),
        retry: .never,
        storage: storage
    )
    let firstClient = QueryClient(defaultFetchOptions: options)
    let secondClient = QueryClient(defaultFetchOptions: options)
    let counter = QueryCounter()
    let persistedFetch = Fetch(key: ["persisted", "invalidated"]) {
        await counter.next()
    }

    let first = try await firstClient.fetch(persistedFetch)

    await firstClient.invalidateQueries(
        matching: QueryFilter(key: ["persisted"], exact: false),
        refetch: .none
    )

    let second = try await secondClient.fetch(persistedFetch)

    #expect(first == 1)
    #expect(second == 2)
    #expect(await counter.value == 2)
}
