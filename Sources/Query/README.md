# VLQuery

`VLQuery` is an actor-backed TanStack Query-style cache for Swift concurrency.

It is memory-only by default and supports:

- stable query keys
- in-flight request deduplication
- stale-time checks
- retry policies
- query invalidation
- async observation
- SwiftUI integration
- optional app-provided persistence
- observable mutation lifecycles
- mutation retries and lifecycle callbacks

## Importing

Import `VLQuery` directly:

```swift
import VLQuery
```

Or through the foundation umbrella product if the app already imports `VerityLabsFoundation`.

## Creating A Client

The default client is memory-only:

```swift
let queryClient = QueryClient()
```

Configure default fetch and cache behavior with `FetchOptions`:

```swift
let queryClient = QueryClient(
    defaultFetchOptions: FetchOptions(
        staleTime: .seconds(60),
        garbageCollectionTime: .seconds(300),
        retry: .maxAttempts(3)
    ),
    defaultMutationOptions: MutationDefaultOptions(
        retry: .never
    )
)
```

Query and mutation defaults are configured independently. Mutations inherit the client's retry policy and delay unless those fields are overridden in `MutationOptions`.

## Query Keys

Query keys are structured arrays:

```swift
let feedKey: QueryKey = ["feed"]
let userKey: QueryKey = ["user", .uuid(userId)]
let commentsKey: QueryKey = ["comments", .uuid(postId)]
```

Use stable keys that describe the data being fetched. Prefixes are used for invalidation, so `["user"]` can match `["user", .uuid(userId)]`.

## Fetching Data

Define cached async work with an immutable `Fetch` value:

```swift
let userFetch = Fetch(key: ["user", .uuid(userId)]) {
    try await api.fetchUser(id: userId)
}

let user: UserProfileUI = try await queryClient.fetch(userFetch)
```

`Fetch` only describes the key, options, and operation. `QueryClient` owns all runtime state. The same descriptor can be fetched, prefetched, observed, or passed to SwiftUI without repeating its configuration:

```swift
await queryClient.prefetch(userFetch)
```

If another task asks for the same key while the first fetch is running, both await the same in-flight task. If cached data is fresh, the cached value is returned immediately.

## Fetch State

Use `state(using:)` when a UI or model needs live cache state. `FetchState` uses Swift Observation and is isolated to the main actor:

```swift
struct UserScreen: View {
    @State private var userState: FetchState<UserProfileUI>

    init(queryClient: QueryClient, userFetch: Fetch<UserProfileUI>) {
        self._userState = State(initialValue: userFetch.state(using: queryClient))
    }

    var body: some View {
        UserProfileView(user: userState.data)
            .overlay {
                if userState.isFetching {
                    ProgressView()
                }
            }
    }
}
```

Call `try await userState.refetch()` to explicitly refresh it. `FetchState` exposes the current `snapshot` along with convenience properties for `status`, `data`, `error`, `isFetching`, `isLoading`, `isRefetching`, and `isStale`.

`QuerySnapshot` includes `status`, `isFetching`, `data`, `error`, `updatedAt`, and `isStale`. `status` describes the available result, while `isFetching` indicates whether a request is currently running. This allows cached data to remain successful during a background refresh.

## SwiftUI

`VLQuery` includes a SwiftUI environment value and a `QueryView`.

Install a client near the app root:

```swift
@main
struct AppMain: App {
    private let queryClient = QueryClient(
        defaultFetchOptions: FetchOptions(staleTime: .seconds(60))
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .queryClient(queryClient)
        }
    }
}
```

Use `QueryView` to bind query state directly to view rendering:

```swift
let userFetch = Fetch(key: ["user", .uuid(userId)]) {
    try await api.fetchUser(id: userId)
}

QueryView(userFetch) { snapshot in
    switch snapshot.status {
    case .pending:
        ProgressView()
    case .success:
        if let user = snapshot.data {
            UserProfileView(user: user)
        }
    case .failure:
        ErrorView(error: snapshot.error)
    }
}
```

`QueryView` uses the `QueryClient` from SwiftUI environment and renders an observable `FetchState` for the supplied fetch.

## Updating Cached Data

Set cached data directly:

```swift
await queryClient.setQueryData(key: ["user", .uuid(userId)], user)
```

Update existing cached data:

```swift
await queryClient.updateQueryData(key: ["user", .uuid(userId)], as: UserProfileUI.self) { user in
    user.name = "Updated Name"
}
```

Read cached data:

```swift
let user: UserProfileUI? = await queryClient.getQueryData(key: ["user", .uuid(userId)])
```

## Invalidating Queries

Invalidate a single exact key:

```swift
await queryClient.invalidateQueries(
    matching: QueryFilter(key: ["user", .uuid(userId)], exact: true)
)
```

Invalidate by prefix:

```swift
await queryClient.invalidateQueries(
    matching: QueryFilter(key: ["user"])
)
```

By default, active observers refetch after invalidation. To only mark matching queries stale:

```swift
await queryClient.invalidateQueries(
    matching: QueryFilter(key: ["feed"]),
    refetch: .none
)
```

## Mutations

Create mutations through `QueryClient`. Mutations execute independently and are not deduplicated or cached:

```swift
let followUser: Mutation<UUID, User, Void> = queryClient.createMutation { userId in
    try await api.followUser(id: userId)
}

try await followUser.mutate(userId)
```

Mutations are not retried by default. Configure retries and awaited lifecycle callbacks with `MutationOptions`. Retry values omitted here inherit from the client's default mutation options:

```swift
let options = MutationOptions<UUID, User, Void>(
    retry: .maxAttempts(2),
    onSuccess: { _, userId, _ in
        await queryClient.invalidateQueries(
            matching: QueryFilter(key: ["user", .uuid(userId)])
        )
    },
    onSettled: { _, _, _, _ in
        await analytics.finishedFollowingUser()
    }
)

let followUser = queryClient.createMutation(
    options: options
) { userId in
    try await api.followUser(id: userId)
}
```

Callbacks run in this order:

1. `onMutate`
2. the mutation operation, including retries
3. `onSuccess` or `onError`
4. `onSettled`

Each callback is awaited. The mutation remains pending until its success or failure callbacks finish.

`onMutate` can return context for optimistic updates and rollback:

```swift
struct OptimisticUpdateContext: Sendable {
    let previousUser: User
}

let options = MutationOptions<UpdateUser, User, OptimisticUpdateContext>(
    onMutate: { update in
        let previousUser: User = await queryClient.getQueryData(key: ["user", .uuid(update.id)])!
        await queryClient.setQueryData(
            key: ["user", .uuid(update.id)],
            previousUser.applying(update)
        )
        return OptimisticUpdateContext(previousUser: previousUser)
    },
    onError: { _, update, context in
        guard let context else { return }
        await queryClient.setQueryData(
            key: ["user", .uuid(update.id)],
            context.previousUser
        )
    }
)
```

Observe mutation state as an async stream:

```swift
for await snapshot in followUser.observe() {
    switch snapshot.status {
    case .idle, .pending, .success, .failure:
        break
    }
}
```

`MutationSnapshot` exposes status, variables, returned data, error, and failure count. When the same mutation object is invoked concurrently, every operation and callback runs, while the latest invocation owns the visible snapshot state.

Reset the visible mutation state when a screen or workflow no longer needs to display the previous result:

```swift
await followUser.reset()
```

`reset()` clears the snapshot back to `.idle`, including its variables, data, error, and failure count. It does not cancel an in-flight mutation or prevent its callbacks from running. If called while a mutation is running, that invocation continues in the background but no longer changes the visible snapshot when it completes.

## Optional Persistence

`VLQuery` does not ship a file, database, or user defaults storage implementation. Memory is the only built-in storage behavior.

Apps can opt into persistence by providing a `QueryStorage` implementation:

```swift
public protocol QueryStorage: Sendable {
    func get<Value: Codable & Sendable>(key: String, as type: Value.Type) async throws -> Value?
    func save<Value: Codable & Sendable>(_ value: Value, key: String) async throws
    func delete(key: String) async throws
}
```

Then pass it through options:

```swift
let queryClient = QueryClient(
    defaultFetchOptions: FetchOptions(storage: appQueryStorage)
)
```

When storage is provided, `Codable & Sendable` query values use the same public APIs. The client handles converting `QueryKey` values into stable string keys and stores its own query metadata envelope.

## Removing Data

Remove matching queries:

```swift
await queryClient.removeQueries(matching: QueryFilter(key: ["user"]))
```

Clear all currently tracked queries:

```swift
await queryClient.clear()
```
