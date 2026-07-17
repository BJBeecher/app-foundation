import SwiftUI
import VLQuery

public struct PaginationAsyncView<
    Value: Codable & Sendable,
    Item: Sendable,
    Content: View
>: View {
    @Environment(\.queryClient) private var queryClient
    @State private var failedCursor: String?
    @State private var loadingMore = false

    private let pagination: PaginationConfiguration<Value, Item>
    private let paginationDirection: PaginationDirection
    private let content: (Binding<Value>) -> Content

    public init(
        pagination: PaginationConfiguration<Value, Item>,
        direction: PaginationDirection = .append,
        @ViewBuilder content: @escaping (Binding<Value>) -> Content
    ) {
        self.pagination = pagination
        self.paginationDirection = direction
        self.content = content
    }

    public init(
        pagination: PaginationConfiguration<Value, Item>,
        direction: PaginationDirection = .append,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.pagination = pagination
        self.paginationDirection = direction
        self.content = { content($0.wrappedValue) }
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
                        LazyVStack(spacing: 16) {
                            let binding = Binding(
                                get: { value },
                                set: { value in
                                    Task {
                                        await queryClient.setQueryData(key: pagination.initial.key, value)
                                    }
                                }
                            )

                            if pagination.items(value).isEmpty {
                                ZStack {
                                    content(binding)
                                    ContentUnavailableView(
                                        "Nothing here yet",
                                        systemImage: "tray"
                                    )
                                }
                                .containerRelativeFrame(.vertical)
                            } else {
                                if paginationDirection == .prepend {
                                    loadingMoreView(cursor: pagination.cursor(value))
                                }

                                content(binding)

                                if paginationDirection == .append {
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
