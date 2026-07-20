import SwiftUI
import VLQuery

public struct QueryView<Value: Codable & Sendable, Content: View>: View {
    @QueryState private var query: Query<Value>

    private let content: (Query<Value>) -> Content

    public init(
        _ fetch: Fetch<Value>,
        @ViewBuilder content: @escaping (Query<Value>) -> Content
    ) {
        self._query = QueryState(fetch)
        self.content = content
    }

    public var body: some View {
        content(query)
    }
}
