//
//  File.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 2/8/25.
//

import VLExtensions
import VLCache
import Foundation

public struct File: Cacheable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let contentType: ContentType
    
    public var data: Data {
        get throws {
            try Data(contentsOf: url)
        }
    }
    
    public init(id: UUID, url: URL, contentType: ContentType) {
        self.id = id
        self.url = url
        self.contentType = contentType
    }
}

public extension File {
    static let sample = File(
        id: UUID(),
        url: .sample,
        contentType: .webP
    )
    
    static let sample2 = File(
        id: UUID(),
        url: .sample2,
        contentType: .webP
    )
    
    static let sample3 = File(
        id: UUID(),
        url: .sample3,
        contentType: .webP
    )
    
    static let sample4 = File(
        id: UUID(),
        url: .sample,
        contentType: .webP
    )
}
