import SwiftUI
import VLQuery

public struct AsyncPager<
    Value: Codable & Sendable,
    Item: Identifiable & Sendable,
    Content: View
>: View {
    @Environment(\.queryClient) private var queryClient
    @State private var failedCursor: String?
    @State private var internalSelectedItem: Item.ID?
    @State private var loadingMore = false

    private var externalSelectedItem: Binding<Item.ID?>?
    private let pagination: PaginationConfiguration<Value, Item>
    private let paginationDirection: PaginationDirection
    private let content: (Item) -> Content

    public init(
        pagination: PaginationConfiguration<Value, Item>,
        direction: PaginationDirection = .append,
        initialPosition: Item.ID? = nil,
        selectedItem: Binding<Item.ID?>? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.pagination = pagination
        self.paginationDirection = direction
        self.externalSelectedItem = selectedItem
        self._internalSelectedItem = State(initialValue: initialPosition)
        self.content = content
    }

    private var selectedItem: Binding<Item.ID?> {
        externalSelectedItem ?? $internalSelectedItem
    }

    public var body: some View {
        QueryView(pagination.initial) { snapshot in
            ZStack {
                switch snapshot.status {
                case .pending:
                    ProgressView()
                        .tint(.secondary)
                        .padding(24)
                case .success:
                    if let value = snapshot.data {
                        let items = pagination.items(value)
                        if items.isEmpty {
                            ContentUnavailableView(
                                "Nothing here yet",
                                systemImage: "tray"
                            )
                        } else {
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 0) {
                                    if paginationDirection == .prepend {
                                        loadingMoreView(cursor: pagination.cursor(value))
                                    }

                                    ForEach(items) { item in
                                        content(item)
                                    }
                                    .containerRelativeFrame(.horizontal, count: 1, spacing: 0)

                                    if paginationDirection == .append {
                                        loadingMoreView(cursor: pagination.cursor(value))
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollIndicators(.hidden)
                            .scrollTargetBehavior(.paging)
                            .scrollPosition(id: selectedItem)
                        }
                    }
                case .failure:
                    ContentUnavailableView(
                        "Something went wrong",
                        systemImage: "exclamationmark.icloud"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func loadingMoreView(cursor: String?) -> some View {
        if let cursor {
            if failedCursor == cursor {
                Button {
                    loadPage(cursor: cursor)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Retry loading")
            } else if !loadingMore {
                ProgressView()
                    .tint(.secondary)
                    .onAppear {
                        loadPage(cursor: cursor)
                    }
            }
        }
    }

    private func loadPage(cursor: String) {
        Task { @MainActor in
            guard !loadingMore else { return }
            failedCursor = nil
            loadingMore = true
            defer { loadingMore = false }

            do {
                try await pagination.fetchPage(
                    using: queryClient,
                    cursor: cursor,
                    direction: paginationDirection
                )
            } catch {
                failedCursor = cursor
            }
        }
    }
}
