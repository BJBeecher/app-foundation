import Foundation
import Observation
import Testing
@testable import VLViews
import VLQuery

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.withLock { value = true }
    }

    func get() -> Bool {
        lock.withLock { value }
    }
}

private actor PageCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct TestItem: Codable, Equatable, Identifiable, Sendable {
    let id: Int
}

private struct TestPage: Codable, Equatable, Sendable {
    var cursor: String?
    var items: [TestItem]
}

@Test
func testPaginationConfigurationMergesAndDeduplicatesPages() async throws {
    let client = QueryClient(defaultFetchOptions: FetchOptions(staleTime: .seconds(60), retry: .never))
    let counter = PageCounter()
    let pagination = PaginationConfiguration(
        initial: Fetch(key: ["feed"]) {
            TestPage(cursor: "next", items: [TestItem(id: 1)])
        },
        cursor: { $0.cursor },
        items: { $0.items },
        page: { _ in
            try await Task.sleep(for: .milliseconds(50))
            await counter.increment()
            return TestPage(cursor: nil, items: [TestItem(id: 2)])
        },
        merge: { cached, page, direction in
            switch direction {
            case .append:
                cached.items += page.items
            case .prepend:
                cached.items = page.items + cached.items
            }
            cached.cursor = page.cursor
        }
    )

    _ = try await client.fetch(pagination.initial)

    try await withThrowingTaskGroup(of: TestPage.self) { group in
        for _ in 0..<4 {
            group.addTask {
                try await pagination.fetchPage(
                    using: client,
                    cursor: "next",
                    direction: .append
                )
            }
        }
        for try await _ in group {}
    }

    let page: TestPage? = await client.getQueryData(key: ["feed"])
    #expect(page == TestPage(cursor: nil, items: [TestItem(id: 1), TestItem(id: 2)]))
    #expect(await counter.value == 1)
}

@Test @MainActor
func testPaginationItemStorageOnlyInvalidatesForChangedItems() {
    let storage = PaginationItemStorage(TestItem(id: 1))
    let equalChange = LockedFlag()
    withObservationTracking {
        _ = storage.item
    } onChange: {
        equalChange.set()
    }

    storage.update(TestItem(id: 1))
    #expect(equalChange.get() == false)

    let differentChange = LockedFlag()
    withObservationTracking {
        _ = storage.item
    } onChange: {
        differentChange.set()
    }

    storage.update(TestItem(id: 2))
    #expect(differentChange.get())
}
