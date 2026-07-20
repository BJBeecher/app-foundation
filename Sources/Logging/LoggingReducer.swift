//
//  LoggingReducer.swift
//  Albumo
//
//  Created by BJ Beecher on 9/3/25.
//

import ComposableArchitecture

@Reducer
public struct LoggingReducer<State, Action> {
    private let logger: LoggingService
    
    public init(logger: LoggingService) {
        self.logger = logger
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            logger.info("\(action)")
            return .none
        }
    }
}
