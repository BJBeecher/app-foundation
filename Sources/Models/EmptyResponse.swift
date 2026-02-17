//
//  EmptyResponse.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 1/31/25.
//

import Foundation

public struct EmptyResponse: DataAccessObject {
    public init() {}
}

extension EmptyResponse {
    static public let sample = EmptyResponse()
}
