//
//  PaginationAsyncView.swift
//  Albumo
//
//  Created by BJ Beecher on 11/21/25.
//

import ComposableArchitecture
import Dependencies
import VLData
import VLLogging
import SwiftUI

public struct PaginationAsyncView<UI: Paginateable, Content: View>: View {
    @Dependency(\.dataService) private var dataAccessService
    @Dependency(\.loggingService) private var loggingService
    
    @State private var store: StoreOf<AsyncFeature<UI>>
    @ViewBuilder let content: (Binding<UI>) -> Content
    @State private var loadingMore = false
    private let paginationDirection: PaginationDirection
    
    public init(
        endpoint: DataAccessor<UI>,
        direction: PaginationDirection = .append,
        @ViewBuilder content: @escaping (Binding<UI>) -> Content
    ) {
        self.store = StoreOf<AsyncFeature<UI>>(initialState: .init(accessor: endpoint)) {
            AsyncFeature()
        }
        self.paginationDirection = direction
        
        self.content = content
    }
    
    public init(
        endpoint: DataAccessor<UI>,
        direction: PaginationDirection = .append,
        @ViewBuilder content: @escaping (UI) -> Content
    ) {
        self.store = StoreOf<AsyncFeature<UI>>(initialState: .init(accessor: endpoint)) {
            AsyncFeature()
        }
        self.paginationDirection = direction
        
        self.content = { content($0.wrappedValue) }
    }
    
    public var body: some View {
        ZStack {
            switch store.loadState {
            case .idle:
                ProgressView()
                    .tint(.secondary)
                    .padding(24)
                    .onAppear {
                        store.send(.load(refresh: false))
                    }
                
            case .loading:
                ProgressView()
                    .tint(.secondary)
                    .padding(24)
                
            case .success(let ui):
                LazyVStack(spacing: 16) {
                    if let binding = Binding($store.value) {
                        if ui.items.isEmpty {
                            ZStack {
                                content(binding)

                                ContentUnavailableView(
                                    "Nothing here yet",
                                    systemImage: "tray"
                                )
                            }.containerRelativeFrame(.vertical)
                        } else {
                            if paginationDirection == .prepend {
                                loadingMoreView(cursor: ui.cursor)
                            }

                            content(binding)
                            
                            if paginationDirection == .append {
                                loadingMoreView(cursor: ui.cursor)
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
        .task {
            await store.send(.observe).finish()
        }
    }

    @ViewBuilder
    private func loadingMoreView(cursor: String?) -> some View {
        if let cursor, !loadingMore {
            ProgressView()
                .tint(.secondary)
                .onAppear {
                    Task { @MainActor in
                        loadingMore = true
                        defer { loadingMore = false }

                        do {
                            try await dataAccessService.loadMore(endpoint: store.accessor, cursor: cursor, direction: paginationDirection)
                        } catch {
                            loggingService.error(error.localizedDescription)
                        }
                    }
                }
        }
    }
}
