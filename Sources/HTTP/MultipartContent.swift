//
//  MultipartContent.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 5/19/25.
//

import Foundation
import VLFiles

public struct MultipartBody: Sendable {
    public let content: [Content]
    public let boundary: String

    public init(content: [Content], boundary: String = UUID().uuidString) {
        self.content = content
        self.boundary = boundary
    }
}

extension MultipartBody {
    public struct Content: Sendable {
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
            case .formField:
                "text/plain"
            case .json:
                "application/json"
            case .file(let file):
                file.contentType.headerValue
            }
        }
    }
    
    public enum MultipartContentSource: Sendable {
        case formField(String)
        case json(any Encodable & Sendable, encoder: JSONEncoder = .init())
        case file(File)
    }
}
