//
//  Paginateable.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 11/21/25.
//

import Foundation

public protocol Paginateable: DataAccessObject {
    associatedtype Item: Identifiable where Item.ID == UUID
    
    var cursor: String? { get set }
    var items: [Item] { get set }
}
