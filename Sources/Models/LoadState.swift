//
//  LoadState.swift
//  TapTap
//
//  Created by BJ Beecher on 10/18/23.
//

import Foundation

public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case success(Value)
    case failure(Error)
    
    public var value: Value? {
        if case .success(let value) = self {
            value
        } else {
            nil
        }
    }
    
    public var error: Error? {
        if case .failure(let error) = self {
            error
        } else {
            nil
        }
    }
    
    public func mapValue<T>(_ transform: (Value) -> T) -> LoadState<T> {
        switch self {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .success(let value):
            return .success(transform(value))
        case .failure(let error):
            return .failure(error)
        }
    }
}

extension LoadState: Equatable where Value: Equatable {
    public static func == (lhs: LoadState<Value>, rhs: LoadState<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            true
        case (.loading, .loading):
            true
        case (.success(let lValue), .success(let rValue)):
            lValue == rValue
        case (.failure, .failure):
            true
        default:
            false
        }
    }
}
