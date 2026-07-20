public struct Fetch<Value: Sendable>: Sendable {
    public let key: QueryKey
    public let options: FetchOptions?
    public let operation: @Sendable () async throws -> Value

    public init(
        key: QueryKey,
        options: FetchOptions? = nil,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        self.key = key
        self.options = options
        self.operation = operation
    }
}
