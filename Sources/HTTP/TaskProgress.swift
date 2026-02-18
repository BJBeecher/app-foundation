//
//  Progress.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 5/7/25.
//

public struct TaskProgress: Sendable {
    public var completed: Double
    public let total: Double
    
    public init(completed: Double = 0.0, total: Double) {
        self.completed = completed
        self.total = total
    }
}
