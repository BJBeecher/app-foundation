import SwiftUI
import Testing
@testable import VLQuery

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

private struct PropertyWrapperCompilationView: View {
    @QueryState(Fetch<Int>(key: ["compilation-query"]) { 1 })
    private var query

    @MutationState(MutationOptions<Void, Int> { 1 })
    private var mutation

    var body: some View {
        Text("\(query.data ?? 0)-\(mutation.data ?? 0)")
    }
}
