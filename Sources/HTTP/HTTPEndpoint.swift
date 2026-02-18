//
//  File.swift
//  TapTap
//
//  Created by BJ Beecher on 9/18/23.
//

import VLExtensions
import Foundation
import VLSharedModels

public enum HTTPMethod {
    case get
    case post
    case patch
    case put
    case delete
    
    var value: String {
        switch self {
        case .get:
            return "GET"
        case .post:
            return "POST"
        case .patch:
            return "PATCH"
        case .put:
            return "PUT"
        case .delete:
            return "DELETE"
        }
    }
}

public struct HTTPEndpoint<Output: Decodable>: @unchecked Sendable {
    public let baseUrl: URL
    public let path: String
    public let method: HTTPMethod
    public let body: Encodable?
    public let bodyParameters: [String: Any]?
    public let headers: [String: String]
    public var queryParameters: [URLQueryItem]?
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder

    public var requestKey: String? {
        guard let request = try? request() else {
            return nil
        }
        
        let method = request.httpMethod ?? ""
        let url = request.url?.absoluteString ?? ""
        let headers = request.allHTTPHeaderFields?
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&") ?? ""
        let body = request.httpBody?.base64EncodedString() ?? ""
        
        return "\(method)|\(url)|\(headers)|\(body)"
    }
    
    public init(
        baseUrl: URL,
        path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        bodyParameters: [String: Any]? = nil,
        headers: [String : String] = [:],
        queryParameters: [URLQueryItem]? = nil,
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init()
    ) {
        self.baseUrl = baseUrl
        self.path = path
        self.method = method
        self.body = body
        self.bodyParameters = bodyParameters
        self.headers = headers
        self.queryParameters = queryParameters
        self.encoder = encoder
        self.decoder = decoder
    }
    
    public func request() throws -> URLRequest {
        var components = URLComponents()
        components.scheme = baseUrl.scheme
        components.host = baseUrl.host
        components.path = baseUrl.path + self.path
        components.queryItems = self.queryParameters
        
        guard let url = components.url else {
            throw GenericError(message: "Bad components: \(components)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.value
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "Timezone")
        
        for header in self.headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }
        
        if let bodyParameters {
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyParameters)
        }
        
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        
        return request
    }
}

// MARK: Endpoints

