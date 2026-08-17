//
//  Logger.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 11/20/25.
//

import Foundation
import os

public protocol LoggingService: Sendable {
    func debug(_ message: String)
    func info(_ message: String)
    func error(_ message: String)
    func critical(_ message: String)
}

public final class OSLoggingService: LoggingService {
    private let logger: Logger

    public init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "",
        category: String = "general"
    ) {
        logger = Logger(subsystem: subsystem, category: category)
    }
    
    public func debug(_ message: String) {
        logger.debug("\(message)")
    }
    
    public func info(_ message: String) {
        logger.info("\(message)")
    }
    
    public func error(_ message: String) {
        logger.error("\(message)")
    }
    
    public func critical(_ message: String) {
        logger.critical("\(message)")
    }
}
