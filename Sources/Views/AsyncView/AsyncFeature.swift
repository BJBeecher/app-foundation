//
//  AsyncFeature.swift
//  Albumo
//
//  Created by BJ Beecher on 8/20/25.
//

import Dependencies
import ComposableArchitecture
import VLData
import VLLogging
import VLSharedModels
import Observation
import SwiftUI

@Reducer
public struct AsyncFeature<UI: DataAccessObject>: Sendable {
    @Dependency(\.dataService) private var dataAccessService
    @Dependency(\.loggingService) private var loggingService
    
    @ObservableState
    public struct State: Sendable {
        let accessor: DataAccessor<UI>
        public var loadState: LoadState<UI> = .idle
        
        public var value: UI? {
            loadState.value
        }
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .observe:
                return .run { [accessor = state.accessor] send in
                    guard let cacheId = accessor.cacheId else {
                        throw GenericError(message: "Missing cache id for endpoint: \(accessor)")
                    }
                    
                    for await ui: UI in self.dataAccessService.observe(id: cacheId) {
                        await send(.setLoadState(.success(ui)))
                    }
                } catch: { error, send in
                    await send(.setLoadState(.failure(error)))
                }
                
            case .load(let refresh):
                switch state.loadState {
                case .success:
                    break
                default:
                    state.loadState = .loading
                }
                
                return .run { [state] send in
                    try await self.dataAccessService.load(
                        endpoint: state.accessor,
                        refresh: refresh
                    )
                } catch: { error, send in
                    await send(.setLoadState(.failure(error)))
                }
                
            case .setLoadState(let loadState):
                state.loadState = loadState
            }
            
            return .none
        }
    }
    
    public enum Action {
        case load(refresh: Bool = false)
        case observe
        case setLoadState(LoadState<UI>)
    }
}
