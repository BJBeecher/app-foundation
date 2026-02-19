//
//  AsyncView.swift
//  Albumo
//
//  Created by BJ Beecher on 8/20/25.
//

import ComposableArchitecture
import VLData
import SwiftUI

public struct AsyncView<UI: DataAccessObject, Content: View>: View {
    let content: (StoreOf<AsyncFeature<UI>>) -> Content
    
    @State private var store: StoreOf<AsyncFeature<UI>>
    
    public init(
        endpoint: DataAccessor<UI>,
        @ViewBuilder content: @escaping (StoreOf<AsyncFeature<UI>>) -> Content
    ) {
        self.store = StoreOf<AsyncFeature<UI>>(initialState: .init(accessor: endpoint)) {
            AsyncFeature()
        }
        
        self.content = content
    }
    
    public var body: some View {
        content(store)
            .task {
                await store.send(.observe).finish()
            }
            .task {
                await store.send(.load(refresh: false)).finish()
            }
    }
}
