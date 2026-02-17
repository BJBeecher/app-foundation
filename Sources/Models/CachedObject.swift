//
//  CachedObject.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 11/15/25.
//

import Foundation

public struct CachedObject<Object: Cacheable>: Codable {
    public let expiry: Date?
    public var object: Object
    
    public init(expiry: Date?, object: Object) {
        self.expiry = expiry
        self.object = object
    }
    
    public init(ttlSeconds: TimeInterval, object: Object) {
        let expiry = Date.now.addingTimeInterval(ttlSeconds)
        self.init(expiry: expiry, object: object)
    }
}
