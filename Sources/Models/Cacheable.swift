//
//  Cacheable.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 4/3/25.
//

import Foundation

public protocol Cacheable: Sendable, Codable, Sampleable {}

extension Array: Cacheable where Element: Cacheable {}

extension Set: Cacheable where Element: Cacheable {}

extension String: Cacheable {
    public static let sample = "Sample"
}
