//
//  Sampleable.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 3/28/25.
//

import Foundation

public protocol Sampleable: Sendable {
    static var sample: Self { get }
}

extension Array: Sampleable where Element: Sampleable {
    public static var sample: Array<Element> {
        [.sample]
    }
}

extension Set: Sampleable where Element: Sampleable {
    public static var sample: Set<Element> {
        [.sample]
    }
}
