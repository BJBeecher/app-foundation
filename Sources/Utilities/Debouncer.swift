//
//  Debouncer.swift
//  Rub
//
//  Created by BJ Beecher on 10/2/24.
//

import Dependencies
import Foundation

public actor Debouncer {
    private var tasks = [String: Date]()
    
    public func debounce(id: String, duration: TimeInterval, block: @escaping () async -> Void) async {
        if let executeDate = self.tasks[id], executeDate > .now {
            return
        } else {
            self.tasks[id] = Date.now.addingTimeInterval(duration)
            await block()
        }
    }
}

// MARK: Dependency

extension Debouncer: DependencyKey {
    public static let liveValue = Debouncer()
}
