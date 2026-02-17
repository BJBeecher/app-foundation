//
//  DataAccessObject.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 1/25/26.
//

import Foundation
import Models

public struct DataAccessor<T: Decodable>: Sendable {
    public var endpoint: HTTPEndpoint<T>
    public let cacheId: String?
    public var postActions: [@Sendable (DataService) async throws -> Void] = []
}

