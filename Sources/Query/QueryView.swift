import SwiftUI

public struct QueryView<Value: Codable & Sendable, Content: View>: View {
    @Environment(\.queryClient) private var queryClient

    private let fetch: Fetch<Value>
    private let content: (QuerySnapshot<Value>) -> Content

    public init(
        _ fetch: Fetch<Value>,
        @ViewBuilder content: @escaping (QuerySnapshot<Value>) -> Content
    ) {
        self.fetch = fetch
        self.content = content
    }

    public var body: some View {
        QueryStateView(
            client: queryClient,
            fetch: fetch,
            content: content
        )
        .id(QueryStateID(client: ObjectIdentifier(queryClient), key: fetch.key))
    }
}

private struct QueryStateID: Hashable {
    let client: ObjectIdentifier
    let key: QueryKey
}

private struct QueryStateView<Value: Codable & Sendable, Content: View>: View {
    @State private var state: FetchState<Value>

    let client: QueryClient
    let fetch: Fetch<Value>
    let content: (QuerySnapshot<Value>) -> Content

    init(
        client: QueryClient,
        fetch: Fetch<Value>,
        content: @escaping (QuerySnapshot<Value>) -> Content
    ) {
        self.client = client
        self.fetch = fetch
        self.content = content
        self._state = State(
            initialValue: FetchState(
                fetch: fetch,
                refetchOperation: { try await client.fetch(fetch) }
            )
        )
    }

    var body: some View {
        content(state.snapshot)
            .task {
                await state.consume(updates: client.persistentSnapshots(for: fetch))
            }
    }
}
