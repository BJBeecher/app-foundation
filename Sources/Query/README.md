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

## Fetch Options

`FetchOptions` controls query freshness, retries, garbage collection, and optional persistence:

```swift
FetchOptions(
    staleTime: .seconds(60),
    garbageCollectionTime: .seconds(300),
    retry: .maxAttempts(3),
    retryDelay: .exponentialBackoff(),
    storage: appQueryStorage,
    persistence: .debounced(.milliseconds(250))
)
```

- `staleTime`: how long successful data is considered fresh. Fresh data is returned from cache without running the fetch operation. The default is `.zero`, so cached data is stale immediately.
- `garbageCollectionTime`: how long an unobserved query can remain in memory before it is pruned. Use `nil` to keep unused records indefinitely. The default is `.seconds(300)`.
- `retry`: whether failed fetches should be retried. The default is `.maxAttempts(3)`.
- `retryDelay`: how long to wait between retry attempts. The default is `.exponentialBackoff()`.
- `storage`: optional persistence used for `Codable & Sendable` query values. The default is `nil`, which makes the client memory-only.
- `persistence`: `.immediate` writes every cache change, while `.debounced(Duration)` coalesces nearby writes for the same key. The client default is `.immediate` when storage is configured.

`Fetch` can override the client's default fetch options per query:

```swift
let userFetch = Fetch(
    key: ["user", .uuid(userId)],
    options: FetchOptions(staleTime: .seconds(300), retry: .never)
) {
    try await api.fetchUser(id: userId)
}
```

When a `Fetch` does not provide options, `QueryClient` uses `defaultFetchOptions`.

### Retry Policies

`RetryPolicy` is shared by queries and mutations:

- `.never`: run the operation once.
- `.maxAttempts(Int)`: allow up to the provided number of failures before giving up.
- `.always`: keep retrying until the operation succeeds or the task is cancelled.

`RetryDelay` controls the delay before each retry:

- `.constant(Duration)`: wait the same amount of time before every retry.
- `.exponentialBackoff(initial:maximum:)`: double the delay after each failure up to the maximum. The default starts at 1 second and caps at 30 seconds.
- `RetryDelay { attempt, error in ... }`: provide custom retry timing.

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

`QuerySnapshot` includes `status`, `isFetching`, `data`, `error`, `updatedAt`, and `isStale`. `status` describes the available result, while `isFetching` indicates whether a request is currently running. This allows cached data to remain successful during a background refresh.

## SwiftUI

`VLQuery` includes a SwiftUI environment value and property wrappers for queries and mutations.

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

Use `@QueryState` to bind query state directly to view rendering:

```swift
struct UserScreen: View {
    @QueryState private var user: Query<UserProfileUI>

    init(fetch: Fetch<UserProfileUI>) {
        self._user = QueryState(fetch)
    }

    var body: some View {
        switch user.status {
        case .pending:
            ProgressView()
        case .success:
            if let user = user.data {
                UserProfileView(user: user)
            }
        case .failure:
            ErrorView(error: user.error)
        }
    }
}
```

Query state fields are observed independently. For example, reading `user.data` does not make the
view dependent on `user.isFetching`.

Pass `select:` to `@QueryState` when a view needs only an equatable projection of a larger query.
The selection is not published when unrelated query data changes:

```swift
@QueryState(userFetch, select: { $0.user.name })
private var userName
```

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
let followUser = queryClient.createMutation(
    MutationOptions { userId in
        try await api.followUser(id: userId)
    }
)

try await followUser.mutate(userId)
```

Mutations are not retried by default. Configure retries and awaited lifecycle callbacks with `MutationOptions`. Retry values omitted here inherit from the client's default mutation options:

```swift
let options = MutationOptions<UUID, User>(
    retry: .maxAttempts(2),
    onSuccess: { _, userId, _ in
        await queryClient.invalidateQueries(
            matching: QueryFilter(key: ["user", .uuid(userId)])
        )
    },
    onSettled: { _, _, _, _ in
        await analytics.finishedFollowingUser()
    },
    mutationFn: { userId in
        try await api.followUser(id: userId)
    }
)

let followUser = queryClient.createMutation(options)
```

### Mutation Options

`MutationOptions` controls the mutation operation, retries, and lifecycle callbacks:

```swift
MutationOptions<Variables, Value>(
    retry: .maxAttempts(2),
    retryDelay: .constant(.seconds(1)),
    onSuccess: { value, variables, _ in },
    onError: { error, variables, _ in },
    onSettled: { value, error, variables, _ in },
    mutationFn: { variables in
        try await api.performMutation(variables)
    }
)
```

- `mutationFn`: the required async operation. It receives exactly one `Variables` value and returns `Value`.
- `retry`: optional override for the client's default mutation retry policy. The client default is `.never`.
- `retryDelay`: optional override for the client's default mutation retry delay. The client default is `.exponentialBackoff()`.
- `onSuccess`: runs after `mutationFn` succeeds. It receives the returned value, the variables, and the optional `onMutate` result.
- `onError`: runs after the mutation gives up after all retry attempts. It receives the error, the variables, and the optional `onMutate` result.
- `onSettled`: runs after either success or final failure. It receives the optional value, optional error, variables, and optional `onMutate` result.
- `onMutate`: runs before the mutation operation. Use the `onMutate` initializer when optimistic updates need a rollback value.

Like TanStack Query, mutation variables are a single value. Use a domain type when the payload has meaning, or a labeled tuple for lightweight multi-value mutations:

```swift
let options = MutationOptions<(id: UUID, patch: RecipePatch), EmptyResponse> { variables in
    try await api.patchRecipe(id: variables.id, patch: variables.patch)
}

try await mutation.mutate((id: recipeId, patch: patch))
```

Use `Void` when variables are captured by the mutation instead of passed to `mutate`:

```swift
let mutation = queryClient.createMutation(
    MutationOptions<Void, EmptyResponse> { _ in
        try await api.deleteRecipe(id: recipeId)
    }
)

try await mutation.mutate()
```

Callbacks run in this order:

1. `onMutate`
2. the mutation operation, including retries
3. `onSuccess` or `onError`
4. `onSettled`

Each callback is awaited. The mutation remains pending until its success or failure callbacks finish.

`onMutate` can return a result for optimistic updates and rollback. Like TanStack Query's
`TOnMutateResult`, this type belongs to the lifecycle options and is not exposed by the
`Mutation<Variables, Value>` handle:

```swift
struct OptimisticUpdateResult: Sendable {
    let previousUser: User
}

let options = MutationOptions<UpdateUser, User>(
    onMutate: { update in
        let previousUser: User = await queryClient.getQueryData(key: ["user", .uuid(update.id)])!
        await queryClient.setQueryData(
            key: ["user", .uuid(update.id)],
            previousUser.applying(update)
        )
        return OptimisticUpdateResult(previousUser: previousUser)
    },
    onError: { _, update, onMutateResult in
        guard let onMutateResult else { return }
        await queryClient.setQueryData(
            key: ["user", .uuid(update.id)],
            onMutateResult.previousUser
        )
    },
    mutationFn: { update in
        try await api.updateUser(update)
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

## SwiftUI Property Wrappers

`@QueryState` resolves `QueryClient` from the SwiftUI environment, begins observing automatically,
and exposes query state and commands directly:

```swift
struct TodosView: View {
    @QueryState private var todos: Query<[Todo]>

    init(fetch: Fetch<[Todo]>) {
        self._todos = QueryState(fetch)
    }

    var body: some View {
        List(todos.data ?? []) { todo in
            Text(todo.title)
        }
        .refreshable {
            _ = try? await todos.refetch()
        }
    }
}
```

`@MutationState` observes a mutation but never executes it automatically. State and commands are
available directly from the wrapped property:

```swift
struct AddTodoButton: View {
    @MutationState private var addTodo: MutationState<TodoDraft, Todo>

    init(options: MutationOptions<TodoDraft, Todo>) {
        self._addTodo = MutationState(options)
    }

    var body: some View {
        Button("Add") {
            Task {
                try await addTodo.mutate(TodoDraft(title: "New todo"))
            }
        }
        .disabled(addTodo.isPending)
    }
}
```

Install the client once above these views:

```swift
ContentView()
    .queryClient(queryClient)
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

Frequently edited caches can coalesce persistence while retaining immediate in-memory updates:

```swift
FetchOptions(
    storage: fileStorage,
    persistence: .debounced(.milliseconds(250))
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

Removing or clearing data publishes a pending snapshot to active observers and keeps those
observers attached. It does not automatically refetch removed data.
