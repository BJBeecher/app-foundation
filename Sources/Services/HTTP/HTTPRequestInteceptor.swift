//
//  HTTPRequestInteceptor.swift
//  app-foundation
//
//  Created by BJ Beecher on 2/17/26.
//

import Foundation

protocol HTTPRequestInteceptor {
    func intercept(_ request: inout URLRequest) async throws
}
