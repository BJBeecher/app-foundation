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

    func get<Value: Codable & Sendable>(key: String, as type: Value.Type) async throws -> Value? {
        guard let data = values[key] else { return nil }
        return try decoder.decode(Value.self, from: data)
    }

    func save<Value: Codable & Sendable>(_ value: Value, key: String) async throws {
        values[key] = try encoder.encode(value)
    }

    func delete(key: String) async throws {
        values[key] = nil
    }
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
