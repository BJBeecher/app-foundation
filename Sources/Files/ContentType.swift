//
//  ContentType.swift
//  Rub
//
//  Created by BJ Beecher on 3/21/24.
//

import Foundation

public enum ContentType: Codable, Sendable {
    case webP
    case multipart
    case jpeg
}

public extension ContentType {
    var ext: String {
        switch self {
        case .jpeg:
            "jpg"
        case .webP:
            "webp"
        case .multipart:
            "tmp"
        }
    }
    
    var headerValue: String {
        switch self {
        case .jpeg:
            "image/jpeg"
        case .webP:
            "image/webp"
        case .multipart:
            "multipart/form-data"
        }
    }
}
