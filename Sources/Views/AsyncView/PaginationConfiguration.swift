import VLQuery

public enum PaginationDirection: Sendable, Equatable {
    case append
    case prepend
}

public struct PaginationConfiguration<Value: Codable & Sendable, Item: Sendable>: Sendable {
    public let initial: Fetch<Value>
    public let cursor: @Sendable (Value) -> String?
    public let items: @Sendable (Value) -> [Item]
    public let page: @Sendable (_ cursor: String) async throws -> Value
    public let merge: @Sendable (_ cached: inout Value, _ page: Value, _ direction: PaginationDirection) -> Void
    public let replaceItem: (@Sendable (_ cached: inout Value, _ item: Item) -> Void)?

    public init(
        initial: Fetch<Value>,
        cursor: @escaping @Sendable (Value) -> String?,
        items: @escaping @Sendable (Value) -> [Item],
        page: @escaping @Sendable (_ cursor: String) async throws -> Value,
        replaceItem: (@Sendable (_ cached: inout Value, _ item: Item) -> Void)? = nil,
        merge: @escaping @Sendable (
            _ cached: inout Value,
            _ page: Value,
            _ direction: PaginationDirection
        ) -> Void
    ) {
        self.initial = initial
        self.cursor = cursor
        self.items = items
        self.page = page
        self.replaceItem = replaceItem
        self.merge = merge
    }

    @discardableResult
    func fetchPage(
        using client: QueryClient,
        cursor: String,
        direction: PaginationDirection
    ) async throws -> Value {
        let key = QueryKey(
            initial.key.parts + [.string("page"), .string(cursor)]
        )
        var pageOptions = initial.options ?? FetchOptions()
        pageOptions.staleTime = .zero

        return try await client.fetch(
            Fetch(
                key: key,
                options: pageOptions,
                operation: {
                    let nextPage = try await self.page(cursor)
                    await client.updateQueryData(key: initial.key, as: Value.self) { cached in
                        merge(&cached, nextPage, direction)
                    }
                    return nextPage
                }
            )
        )
    }
}
