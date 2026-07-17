# VLViews

`VLViews` provides reusable SwiftUI components that build on `VLQuery`.

## Async Content

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

Use the same configuration for a list or pager:

```swift
PaginationAsyncView(pagination: feedPagination) { feed in
    FeedView(feed: feed)
}

AsyncPager(pagination: feedPagination) { post in
    PostView(post: post)
}
```

Page requests use cursor-specific `Fetch` values internally, so `QueryClient` still deduplicates concurrent requests without knowing anything about pagination.
