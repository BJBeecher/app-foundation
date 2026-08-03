import Observation
import SwiftUI
import VLQuery

public struct PaginationAsyncView<
    Value: Codable & Sendable,
    Item: Identifiable & Equatable & Sendable,
    Content: View,
    EmptyContent: View
>: View where Item.ID: Sendable {
    @Environment(\.queryClient) private var queryClient
    @State private var storage: PaginationStorage<Value, Item>
    @State private var failedCursor: String?
    @State private var loadingMore = false

    private let pagination: PaginationConfiguration<Value, Item>
    private let direction: PaginationDirection
    private let content: (Binding<Item>) -> Content
    private let emptyContent: () -> EmptyContent

    public init(
        pagination: PaginationConfiguration<Value, Item>,
        direction: PaginationDirection = .append,
        @ViewBuilder content: @escaping (Binding<Item>) -> Content,
        @ViewBuilder empty: @escaping () -> EmptyContent
    ) {
        self.pagination = pagination
        self.direction = direction
        self.content = content
        self.emptyContent = empty
        self._storage = State(
            initialValue: PaginationStorage(pagination: pagination)
        )
    }

    public var body: some View {
        ZStack {
            switch storage.status {
            case .pending:
                ProgressView()
                    .tint(.secondary)
                    .padding(24)
            case .success:
                if storage.itemIDs.isEmpty {
                    emptyContent()
                } else {
                    LazyVStack(spacing: 16) {
                        if direction == .prepend {
                            loadingMoreView(cursor: storage.cursor)
                        }

                        ForEach(storage.itemIDs, id: \.self) { id in
                            if let item = storage.itemStorage(for: id) {
                                PaginationItemView(
                                    storage: item,
                                    update: storage.update,
                                    content: content
                                )
                            }
                        }

                        if direction == .append {
                            loadingMoreView(cursor: storage.cursor)
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
        .task(id: PaginationObservationID(
            key: pagination.initial.key,
            client: ObjectIdentifier(queryClient)
        )) {
            await storage.observe(pagination: pagination, using: queryClient)
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
                    direction: direction
                )
            } catch {
                failedCursor = cursor
            }
        }
    }
}

public extension PaginationAsyncView where EmptyContent == DefaultPaginationEmptyView {
    init(
        pagination: PaginationConfiguration<Value, Item>,
        direction: PaginationDirection = .append,
        @ViewBuilder content: @escaping (Binding<Item>) -> Content
    ) {
        self.init(
            pagination: pagination,
            direction: direction,
            content: content,
            empty: { DefaultPaginationEmptyView() }
        )
    }
}

public struct DefaultPaginationEmptyView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "Nothing here yet",
            systemImage: "tray"
        )
        .containerRelativeFrame(.vertical)
    }
}

@MainActor
@Observable
final class PaginationStorage<
    Value: Codable & Sendable,
    Item: Identifiable & Equatable & Sendable
> where Item.ID: Sendable {
    private(set) var status: QueryStatus = .pending
    private(set) var cursor: String?
    private(set) var itemIDs: [Item.ID] = []

    @ObservationIgnored private var pagination: PaginationConfiguration<Value, Item>
    @ObservationIgnored private var itemStorage: [Item.ID: PaginationItemStorage<Item>] = [:]
    @ObservationIgnored private var queryClient: QueryClient?
    @ObservationIgnored private var updateTasks: [Item.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var updateRevisions: [Item.ID: UInt64] = [:]
    @ObservationIgnored private var dataRevision: UInt64 = 0

    init(pagination: PaginationConfiguration<Value, Item>) {
        self.pagination = pagination
    }

    func observe(
        pagination: PaginationConfiguration<Value, Item>,
        using queryClient: QueryClient
    ) async {
        if self.pagination.initial.key != pagination.initial.key {
            reset()
        }
        self.pagination = pagination
        self.queryClient = queryClient
        for await snapshot in queryClient.observe(pagination.initial) {
            guard !Task.isCancelled else { return }
            apply(snapshot)
        }
    }

    func itemStorage(for id: Item.ID) -> PaginationItemStorage<Item>? {
        itemStorage[id]
    }

    func update(_ item: Item) {
        itemStorage[item.id]?.update(item)

        guard queryClient != nil, pagination.replaceItem != nil else {
            assertionFailure("Item-scoped pagination requires a replaceItem closure")
            return
        }

        updateTasks[item.id]?.cancel()
        updateRevisions[item.id, default: 0] &+= 1
        let revision = updateRevisions[item.id, default: 0]
        updateTasks[item.id] = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            await self?.commit(item, revision: revision)
        }
    }

    private func commit(_ item: Item, revision: UInt64) async {
        guard updateRevisions[item.id] == revision,
              let queryClient,
              let replaceItem = pagination.replaceItem else {
            return
        }
        await queryClient.updateQueryData(
            key: pagination.initial.key,
            as: Value.self
        ) { value in
            replaceItem(&value, item)
        }
        if updateRevisions[item.id] == revision {
            updateTasks[item.id] = nil
        }
    }

    private func apply(_ snapshot: QuerySnapshot<Value>) {
        if status != snapshot.status {
            status = snapshot.status
        }
        guard dataRevision != snapshot.dataRevision else { return }
        dataRevision = snapshot.dataRevision
        guard let value = snapshot.data else { return }

        let items = pagination.items(value)
        let ids = items.map(\.id)
        for item in items {
            if let storage = itemStorage[item.id] {
                storage.update(item)
            } else {
                itemStorage[item.id] = PaginationItemStorage(item)
            }
        }
        let idSet = Set(ids)
        for id in itemStorage.keys.filter({ !idSet.contains($0) }) {
            updateTasks[id]?.cancel()
            updateTasks[id] = nil
            updateRevisions[id] = nil
        }
        itemStorage = itemStorage.filter { idSet.contains($0.key) }

        if itemIDs != ids {
            itemIDs = ids
        }

        let cursor = pagination.cursor(value)
        if self.cursor != cursor {
            self.cursor = cursor
        }
    }

    private func reset() {
        updateTasks.values.forEach { $0.cancel() }
        updateTasks.removeAll()
        updateRevisions.removeAll()
        itemStorage.removeAll()
        dataRevision = 0
        status = .pending
        cursor = nil
        itemIDs = []
    }
}

@MainActor
@Observable
final class PaginationItemStorage<Item: Equatable & Sendable> {
    private(set) var item: Item

    init(_ item: Item) {
        self.item = item
    }

    func update(_ item: Item) {
        if self.item != item {
            self.item = item
        }
    }
}

private struct PaginationItemView<
    Item: Identifiable & Equatable & Sendable,
    Content: View
>: View {
    let storage: PaginationItemStorage<Item>
    let update: @MainActor (Item) -> Void
    let content: (Binding<Item>) -> Content

    var body: some View {
        content(
            Binding(
                get: { storage.item },
                set: { update($0) }
            )
        )
    }
}

private struct PaginationObservationID: Hashable {
    let key: QueryKey
    let client: ObjectIdentifier
}
