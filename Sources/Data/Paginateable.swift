//
//  Paginateable.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 11/21/25.
//

import Foundation

public enum PaginationDirection: Sendable, Equatable {
    case append
    case prepend
}

public protocol Paginateable: DataAccessObject {
    associatedtype Item: Identifiable where Item.ID == UUID
    
    var cursor: String? { get set }
    var items: [Item] { get set }
}
