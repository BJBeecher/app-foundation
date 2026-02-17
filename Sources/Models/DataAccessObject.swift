//
//  Model.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 3/28/25.
//

import Foundation

public protocol DataAccessObject: Codable, Sendable, Sampleable, Cacheable {}

extension AttributedString: DataAccessObject {
    public static let sample: AttributedString = AttributedString()
}

extension Array: DataAccessObject where Element: DataAccessObject {
    public static var sample: Array<Element> {
        [.sample]
    }
}
