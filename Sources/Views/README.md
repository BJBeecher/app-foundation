# VLViews

`VLViews` provides reusable SwiftUI components that build on `VLQuery`.

## Async Content

Render custom query state with `QueryView`:

```swift
QueryView(userFetch) { query in
    switch query.status {
    case .pending:
        ProgressView()
    case .success:
        UserView(user: query.data)
    case .failure:
        ContentUnavailableView("Unable to load user", systemImage: "person.crop.circle.badge.exclamationmark")
    }
}
```

Render a fetch with standard loading and failure states:

```swift
StandardAsyncView(fetch: userFetch) { user in
    UserView(user: user)
}
```

The binding overload writes changes back to the query cache:

```swift
StandardAsyncView(fetch: settingsFetch) { $settings in
    Toggle("Notifications", isOn: $settings.notificationsEnabled)
}
```

## Pagination

Pagination is view configuration rather than query behavior. Describe how the view reads a cursor and items from the response, fetches a page, and merges it:

```swift
let feedPagination = PaginationConfiguration(
    initial: Fetch(key: ["feed"]) {
        try await api.fetchFeed()
    },
    cursor: { $0.cursor },
    items: { $0.posts },
    page: { cursor in
        try await api.fetchFeed(cursor: cursor)
    },
    replaceItem: { cached, post in
        guard let index = cached.posts.firstIndex(where: { $0.id == post.id }) else { return }
        cached.posts[index] = post
    },
    merge: { cached, page, direction in
        switch direction {
        case .append:
            cached.posts += page.posts
        case .prepend:
            cached.posts = page.posts + cached.posts
        }
        cached.cursor = page.cursor
    }
)
```

`PaginationAsyncView` scopes observation and bindings to each identifiable, equatable item. Updating
one item does not invalidate unchanged rows:

```swift
PaginationAsyncView(pagination: feedPagination) { $post in
    PostView(post: $post)
}

AsyncPager(pagination: feedPagination) { post in
    PostView(post: post)
}
```

Use `PaginationValueAsyncView` for the less common case where content needs the complete immutable
response rather than item-scoped rows.

Page requests use cursor-specific `Fetch` values internally, so `QueryClient` still deduplicates concurrent requests without knowing anything about pagination.
