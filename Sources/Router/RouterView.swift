//
//  RouterView.swift
//  VerityLabsFoundation
//
//  Created by BJ Beecher on 4/23/26.
//

import ComposableArchitecture
import SwiftUI

public struct RouterView<Destination: RouterDestination, Content: View>: View {
    @State private var store: StoreOf<RouterFeature<Destination>>
    
    @Namespace private var routerNamespace
    
    let background: Color?
    let content: (Destination, Namespace.ID) -> Content
    
    public init(background: Color? = nil, routerService: NavigationRouter<Destination>, @ViewBuilder destination: @escaping (Destination, Namespace.ID) -> Content) {
        self._store = SwiftUI.State(initialValue: StoreOf<RouterFeature>(initialState: .init()) {
            RouterFeature(routerService: routerService)
        })
        self.background = background
        self.content = destination
    }
    
    public var body: some View {
        NavigationStack(path: $store.destinations) {
            ProgressView()
                .tint(.secondary)
                .navigationDestination(for: Destination.self) { destination in
                    ZStack {
                        background?
                            .ignoresSafeArea()
                            .zIndex(0)
                        
                        content(destination, routerNamespace)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .zIndex(1)
                    }.environment(\.routerNamespace, routerNamespace)
                }
        }
        .overlay {
            if let loadingString = store.shownLoadingString {
                loadingOverlay(loadingString)
            }
        }
        .sheet(item: $store.presentedSheet.sending(\.sheetDidUpdate)) { destination in
            NavigationStack {
                content(destination, routerNamespace)
            }
        }
        .alert(
            store.presentedAlert?.title ?? "",
            isPresented: $store.isAlertPresented.sending(\.isShowingAlertDidUpdate),
            presenting: store.presentedAlert
        ) { alert in
            ForEach(alert.buttons) { button in
                Button(button.title, role: button.role) {
                    alert.tapped?(button)
                }
            }
        } message: { alert in
            if let message = alert.message {
                Text(message)
            }
        }
        .task {
            await store.send(.observeDestinations).finish()
        }
        .task {
            await store.send(.observeSheets).finish()
        }
        .task {
            await store.send(.observeAlerts).finish()
        }
        .task {
            await store.send(.observeLoader).finish()
        }
        .onChange(of: store.state.destinations) { _, newValue in
            store.send(.destinationsDidUpdate(newValue))
        }
    }

    @ViewBuilder
    private func loadingOverlay(_ loadingString: String) -> some View {
        let base = ProgressView(loadingString)
            .tint(.secondary)
            .padding(24)
            .transition(.scale)

        if #available(iOS 26.0, macOS 26.0, *) {
            base
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        } else {
            base
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
