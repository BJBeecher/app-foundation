//
//  Debouncer.swift
//  Rub
//
//  Created by BJ Beecher on 10/2/24.
//

import Foundation

public actor Debouncer {
    private var tasks = [String: Date]()
    
    public init() {}
    
    public func debounce(id: String, duration: TimeInterval, block: @escaping @Sendable () async -> Void) async {
        if let executeDate = self.tasks[id], executeDate > .now {
            return
        } else {
            self.tasks[id] = Date.now.addingTimeInterval(duration)
            await block()
        }
    }
}
