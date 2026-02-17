//
//  Logger.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 11/20/25.
//

import Foundation
import Dependencies
import os

public protocol LoggingService: Sendable {
    func debug(_ message: String)
    func info(_ message: String)
    func error(_ message: String)
    func critical(_ message: String)
}

final class LoggingServiceLiveValue: LoggingService {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "general")
    
    func debug(_ message: String) {
        logger.debug("\(message)")
    }
    
    func info(_ message: String) {
        logger.info("\(message)")
    }
    
    func error(_ message: String) {
        logger.error("\(message)")
    }
    
    func critical(_ message: String) {
        logger.critical("\(message)")
    }
}

public enum LoggingServiceKey: DependencyKey {
    public static let liveValue: LoggingService = LoggingServiceLiveValue()
}

public extension DependencyValues {
    var loggingService: LoggingService {
        get { self[LoggingServiceKey.self] }
        set { self[LoggingServiceKey.self] = newValue }
    }
}
