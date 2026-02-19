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
    @ViewBuilder let content: (UI) -> Content
    @State private var loadingMore = false
    
    public init(
        endpoint: DataAccessor<UI>,
        @ViewBuilder content: @escaping (UI) -> Content
    ) {
        self.store = StoreOf<AsyncFeature<UI>>(initialState: .init(accessor: endpoint)) {
            AsyncFeature()
        }
        
        self.content = content
    }
    
    public var body: some View {
        ZStack {
            switch store.loadState {
            case .idle:
                ProgressView()
                    .padding(24)
                    .onAppear {
                        store.send(.load(refresh: false))
                    }
                
            case .loading:
                ProgressView()
                    .padding(24)
                
            case .success(let ui):
                LazyVStack(spacing: 16) {
                    content(ui)
                    
                    if let cursor = ui.cursor, !loadingMore {
                        ProgressView()
                            .onAppear {
                                Task { @MainActor in
                                    loadingMore = true
                                    
                                    do {
                                        try await dataAccessService.loadMore(endpoint: store.accessor, cursor: cursor)
                                        loadingMore = false
                                    } catch {
                                        loggingService.error(error.localizedDescription)
                                    }
                                }
                            }
                    }
                }.overlay {
                    if ui.items.isEmpty {
                        ContentUnavailableView(
                            "Nothing here yet",
                            systemImage: "tray"
                        )
                        .padding(.top, 100)
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
        .task {
            await store.send(.observe).finish()
        }
    }
}
