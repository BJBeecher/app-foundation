//
//  AsyncImageDetailsPager.swift
//  Albumo
//
//  Created by BJ Beecher on 2/3/26.
//

import ComposableArchitecture
import Dependencies
import VLData
import VLLogging
import SwiftUI

public struct AsyncPager<UI: Paginateable, Content: View>: View where UI.Item: Identifiable {
    @Dependency(\.dataService) private var dataService
    @Dependency(\.loggingService) private var loggingService
    
    @State private var store: StoreOf<AsyncFeature<UI>>
    @State private var internalSelectedItem: UI.Item.ID?
    private var externalSelectedItem: Binding<UI.Item.ID?>?
    
    private let content: (UI.Item) -> Content
    
    public init(
        endpoint: DataAccessor<UI>,
        initialPosition: UI.Item.ID? = nil,
        selectedItem: Binding<UI.Item.ID?>? = nil,
        @ViewBuilder content: @escaping (UI.Item) -> Content
    ) {
        self._store = State(initialValue: StoreOf<AsyncFeature<UI>>(initialState: .init(accessor: endpoint)) {
            AsyncFeature()
        })
        self._internalSelectedItem = State(initialValue: initialPosition)
        self.externalSelectedItem = selectedItem
        self.content = content
    }
    
    private var selectedItem: Binding<UI.Item.ID?> {
        externalSelectedItem ?? $internalSelectedItem
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
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(ui.items) { item in
                            content(item)
                                
                            if let cursor = ui.cursor {
                                ProgressView()
                                    .onAppear {
                                        Task { @MainActor in
                                            do {
                                                try await dataService.loadMore(endpoint: store.accessor, cursor: cursor)
                                            } catch {
                                                loggingService.error(error.localizedDescription)
                                            }
                                        }
                                    }
                            }
                        }
                        .containerRelativeFrame(.horizontal, count: 1, spacing: 0)
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: selectedItem)
                
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
