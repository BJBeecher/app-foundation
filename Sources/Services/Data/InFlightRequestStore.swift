//
//  InFlightRequestStore.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 2/5/26.
//

import Foundation
import Models

private struct Payload<T>: @unchecked Sendable {
    let value: T
}

actor InFlightRequestStore {
    private var tasks: [String: Task<Payload<Any>, Error>] = [:]
    
    func run<T>(key: String, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        if let existing = tasks[key] {
            let value = try await existing.value
            guard let typed = value as? T else {
                throw GenericError(message: "In-flight response type mismatch.")
            }
            return typed
        }
        
        let task = Task<Payload<Any>, Error> {
            let value = try await operation()
            return Payload(value: value)
        }
        
        tasks[key] = task
        
        defer { tasks[key] = nil }
        
        do {
            let payload = try await task.value
            
            guard let typed = payload.value as? T else {
                throw GenericError(message: "In-flight response type mismatch.")
            }
            
            return typed
        } catch {
            throw error
        }
    }
}
