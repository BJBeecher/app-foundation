//
//  File.swift
//  TapTap
//
//  Created by BJ Beecher on 9/18/23.
//

import VLExtensions
import Foundation
import VLFiles
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

public enum HTTPBody: @unchecked Sendable {
    case file(File)
    case json(any Encodable & Sendable, encoder: JSONEncoder = .init())
    case jsonParameters([String: Any])
    case multipart(MultipartBody)
}

public extension HTTPBody {
    static func multipart(_ content: [MultipartBody.Content]) -> Self {
        .multipart(.init(content: content))
    }
}

public struct HTTPEndpoint<Output: Decodable>: @unchecked Sendable {
    public var url: URL
    public var method: HTTPMethod
    public var body: HTTPBody?
    public var headers: [String: String]
    public var queryParameters: [URLQueryItem]?
    public var decoder: JSONDecoder
    public let intecepters: [HTTPServiceRequestInteceptor]

    public var requestKey: String? {
        guard let url = requestURL?.absoluteString else {
            return nil
        }

        let headers = headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let body = requestKeyBody ?? ""
        
        return "\(method.value)|\(url)|\(headers)|\(body)"
    }

    var requestURL: URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let queryParameters {
            components.queryItems = (components.queryItems ?? []) + queryParameters
        }

        return components.url
    }
    
    public init(
        url: URL,
        method: HTTPMethod = .get,
        body: HTTPBody? = nil,
        headers: [String : String] = [:],
        queryParameters: [URLQueryItem]? = nil,
        decoder: JSONDecoder = .init(),
        inteceptors: [HTTPServiceRequestInteceptor] = []
    ) {
        self.url = url
        self.method = method
        self.body = body
        self.headers = headers
        self.queryParameters = queryParameters
        self.decoder = decoder
        self.intecepters = inteceptors
    }

    public init(
        url: URL,
        method: HTTPMethod = .get,
        body: (any Encodable & Sendable)?,
        headers: [String : String] = [:],
        queryParameters: [URLQueryItem]? = nil,
        decoder: JSONDecoder = .init(),
        inteceptors: [HTTPServiceRequestInteceptor] = []
    ) {
        self.init(
            url: url,
            method: method,
            body: body.map { .json($0) },
            headers: headers,
            queryParameters: queryParameters,
            decoder: decoder,
            inteceptors: inteceptors
        )
    }
    
    private var requestKeyBody: String? {
        guard let body else { return nil }

        switch body {
        case .file(let file):
            return file.url.lastPathComponent
        case .json(let object, let encoder):
            return try? encoder.encode(object).base64EncodedString()
        case .jsonParameters(let parameters):
            return try? JSONSerialization.data(withJSONObject: parameters).base64EncodedString()
        case .multipart(let multipart):
            return multipart.content
                .map(\.name)
                .joined(separator: "&")
        }
    }
}
