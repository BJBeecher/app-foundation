//
//  MultipartContent.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 5/19/25.
//

import Foundation

public struct MultipartContent: Sendable {
    public let name: String
    public let source: MultipartContentSource
    
    public init(
        name: String,
        source: MultipartContentSource
    ) {
        self.name = name
        self.source = source
    }
    
    public var contentType: String {
        switch source {
        case .json:
            "application/json"
        case .file(let file):
            file.contentType.headerValue
        }
    }
}

public enum MultipartContentSource: Sendable {
    case json(any Encodable & Sendable)
    case file(File)
}
