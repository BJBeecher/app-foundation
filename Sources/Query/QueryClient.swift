import Foundation

public actor QueryClient {
    public static let shared = QueryClient()

    var records: [QueryKey: QueryRecord] = [:]
    var observers: [QueryKey: [UUID: QueryObserver]] = [:]
    var observerKeys: [UUID: QueryKey] = [:]
    var persistenceTasks: [QueryKey: Task<Void, Never>] = [:]
    var persistenceRevisions: [QueryKey: UInt64] = [:]
    let defaultFetchOptions: FetchOptions
    nonisolated let defaultMutationOptions: MutationDefaultOptions
    let defaultStorage: QueryStorage?

    public init(
        defaultFetchOptions: FetchOptions = FetchOptions(),
        defaultMutationOptions: MutationDefaultOptions = MutationDefaultOptions()
    ) {
        self.defaultFetchOptions = defaultFetchOptions
        self.defaultMutationOptions = defaultMutationOptions
        self.defaultStorage = defaultFetchOptions.storage
    }

    public nonisolated func createMutation<Variables: Sendable, Value: Sendable>(
        _ options: MutationOptions<Variables, Value>
    ) -> Mutation<Variables, Value> {
        Mutation(
            defaultOptions: defaultMutationOptions,
            options: options
        )
    }
}

public enum QueryClientError: Error, Sendable, Equatable {
    case typeMismatch(QueryKey)
}
