import SwiftUI
import VLQuery

public struct PaginationValueAsyncView<
    Value: Codable & Sendable,
    Item: Sendable,
    Content: View
>: View {
    @State private var failedCursor: String?
    @State private var loadingMore = false

    private let pagination: PaginationConfiguration<Value, Item>
    private let direction: PaginationDirection
    @Environment(\.queryClient) private var queryClient
    private let content: (Value) -> Content

    public init(
        pagination: PaginationConfiguration<Value, Item>,
        direction: PaginationDirection = .append,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.pagination = pagination
        self.direction = direction
        self.content = content
    }

    public var body: some View {
        QueryView(pagination.initial) { query in
            ZStack {
                switch query.status {
                case .pending:
                    ProgressView()
                        .tint(.secondary)
                        .padding(24)
                case .success:
                    if let value = query.data {
                        LazyVStack(spacing: 16) {
                            if pagination.items(value).isEmpty {
                                ZStack {
                                    content(value)
                                    ContentUnavailableView(
                                        "Nothing here yet",
                                        systemImage: "tray"
                                    )
                                }
                                .containerRelativeFrame(.vertical)
                            } else {
                                if direction == .prepend {
                                    loadingMoreView(cursor: pagination.cursor(value))
                                }

                                content(value)

                                if direction == .append {
                                    loadingMoreView(cursor: pagination.cursor(value))
                                }
                            }
                        }
                    }
                case .failure:
                    ContentUnavailableView(
                        "Something went wrong",
                        systemImage: "exclamationmark.icloud"
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func loadingMoreView(cursor: String?) -> some View {
        if let cursor {
            ZStack {
                if failedCursor == cursor {
                    Button {
                        loadPage(cursor: cursor)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Retry loading")
                } else if loadingMore {
                    ProgressView()
                        .tint(.secondary)
                }
            }
            .frame(height: 44)
            .id(cursor)
            .onAppear {
                guard failedCursor != cursor else { return }
                loadPage(cursor: cursor)
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
                    direction: direction
                )
            } catch {
                failedCursor = cursor
            }
        }
    }
}
