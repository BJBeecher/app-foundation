import Observation
import SwiftUI
import Testing
@testable import VLQuery

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

@Test @MainActor
func testQueryPropertyStartsObservationAndExposesState() async throws {
    let key: QueryKey = ["property-query", .uuid(UUID())]
    let fetch = Fetch<Int>(key: key) { 42 }
    var query = QueryState(fetch)

    query.update()

    let state = query.wrappedValue
    for _ in 0..<100 where state.data == nil {
        await Task.yield()
    }

    #expect(state.data == 42)
    #expect(state.status == .success)
    #expect(try await state.refetch() == 42)
}

@Test @MainActor
func testDataObservationIgnoresMetadataOnlySnapshots() async throws {
    let key: QueryKey = ["granular-observation", .uuid(UUID())]
    let fetch = Fetch(key: key, options: FetchOptions(staleTime: .seconds(60))) {
        42
    }
    var query = QueryState(fetch)
    query.update()

    for _ in 0..<100 where query.wrappedValue.data == nil {
        await Task.yield()
    }

    let changed = LockedFlag()
    withObservationTracking {
        _ = query.wrappedValue.data
    } onChange: {
        changed.set()
    }

    await QueryClient.shared.invalidateQueries(
        matching: QueryFilter(key: key, exact: true),
        refetch: .none
    )
    for _ in 0..<10 {
        await Task.yield()
    }

    #expect(changed.get() == false)
}

@Test @MainActor
func testSelectionObservationIgnoresUnchangedSelections() async throws {
    let key: QueryKey = ["selection-observation", .uuid(UUID())]
    let fetch = Fetch(key: key, options: FetchOptions(staleTime: .seconds(60))) {
        [1]
    }
    var selection = QueryState(fetch, select: { $0.count })
    selection.update()

    for _ in 0..<100 where selection.wrappedValue.data == nil {
        await Task.yield()
    }

    let changed = LockedFlag()
    withObservationTracking {
        _ = selection.wrappedValue.data
    } onChange: {
        changed.set()
    }

    await QueryClient.shared.setQueryData(key: key, [2])
    for _ in 0..<10 {
        await Task.yield()
    }

    #expect(changed.get() == false)
}

@Test @MainActor
func testMutationStatePropertyExecutesAndObservesMutation() async throws {
    let options = MutationOptions<Int, Int> { $0 * 2 }
    var mutation = MutationState(options)

    mutation.update()

    #expect(try await mutation.wrappedValue.mutate(3) == 6)
    for _ in 0..<100 where mutation.wrappedValue.data == nil {
        await Task.yield()
    }

    #expect(mutation.wrappedValue.data == 6)
    #expect(mutation.wrappedValue.status == .success)

    await mutation.wrappedValue.reset()
    for _ in 0..<100 where mutation.wrappedValue.status != .idle {
        await Task.yield()
    }
    #expect(mutation.wrappedValue.status == .idle)
}

@Test @MainActor
func testMutationDataObservationIgnoresUnrelatedStateChanges() async {
    var mutation = MutationState(
        MutationOptions<Void, Int>(retry: .never) {
            throw QueryTestMutationError.failed
        }
    )
    mutation.update()

    let changed = LockedFlag()
    withObservationTracking {
        _ = mutation.wrappedValue.data
    } onChange: {
        changed.set()
    }

    _ = try? await mutation.wrappedValue.mutate()
    for _ in 0..<10 {
        await Task.yield()
    }

    #expect(changed.get() == false)
}

private struct PropertyWrapperCompilationView: View {
    @QueryState(Fetch<Int>(key: ["compilation-query"]) { 1 })
    private var query

    @MutationState(MutationOptions<Void, Int> { 1 })
    private var mutation

    @QueryState(
        Fetch<[Int]>(key: ["selection-compilation-query"]) { [1, 2, 3] },
        select: { $0.count }
    )
    private var selection

    var body: some View {
        Text("\(query.data ?? 0)-\(mutation.data ?? 0)-\(selection.data ?? 0)")
    }
}

private enum QueryTestMutationError: Error {
    case failed
}
