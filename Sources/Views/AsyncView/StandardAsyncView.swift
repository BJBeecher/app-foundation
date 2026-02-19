//
//  StandardAsyncView.swift
//  Albumo
//
//  Created by BJ Beecher on 12/18/25.
//

import VLData
import SwiftUI

public struct StandardAsyncView<UI: DataAccessObject, Content: View>: View {
    let endpoint: DataAccessor<UI>
    let content: (UI) -> Content
    
    public init(endpoint: DataAccessor<UI>, @ViewBuilder content: @escaping (UI) -> Content) {
        self.endpoint = endpoint
        self.content = content
    }
    
    public var body: some View {
        AsyncView(endpoint: endpoint) { store in
            switch store.loadState {
            case .idle, .loading:
                ProgressView()
            case .success(let ui):
                content(ui)
            case .failure:
                ContentUnavailableView(
                    "Unable to load content",
                    systemImage: "exclamationmark.icloud"
                )
            }
        }
    }
}
