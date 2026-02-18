//
//  GenericError.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 2/8/25.
//

public struct GenericError: Error {
    public let message: String
    
    public init(message: String) {
        self.message = message
    }
}
