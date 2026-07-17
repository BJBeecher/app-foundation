//
//  File.swift
//  TapTap
//
//  Created by BJ Beecher on 9/18/23.
//

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
    public let interceptors: [HTTPServiceRequestInterceptor]

    var requestURL: URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let queryParameters {
            components.queryItems = (components.queryItems ?? []) + queryParameters
        }

        return components.url
    }

    public func request() throws -> URLRequest {
        guard let requestURL else {
            throw GenericError(message: "Bad endpoint url: \(url)")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method.value
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "Timezone")

        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        switch body {
        case .file(let file):
            request.setValue(file.contentType.headerValue, forHTTPHeaderField: "Content-Type")
        case .json(let object, let encoder):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(object)
        case .jsonParameters(let parameters):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        case .multipart(let multipart):
            request.setValue(
                "multipart/form-data; boundary=\(multipart.boundary)",
                forHTTPHeaderField: "Content-Type"
            )
        case nil:
            break
        }

        return request
    }
    
    public init(
        url: URL,
        method: HTTPMethod = .get,
        body: HTTPBody? = nil,
        headers: [String : String] = [:],
        queryParameters: [URLQueryItem]? = nil,
        decoder: JSONDecoder = .init(),
        interceptors: [HTTPServiceRequestInterceptor] = []
    ) {
        self.url = url
        self.method = method
        self.body = body
        self.headers = headers
        self.queryParameters = queryParameters
        self.decoder = decoder
        self.interceptors = interceptors
    }

    public init(
        url: URL,
        method: HTTPMethod = .get,
        body: (any Encodable & Sendable)?,
        headers: [String : String] = [:],
        queryParameters: [URLQueryItem]? = nil,
        decoder: JSONDecoder = .init(),
        interceptors: [HTTPServiceRequestInterceptor] = []
    ) {
        self.init(
            url: url,
            method: method,
            body: body.map { .json($0) },
            headers: headers,
            queryParameters: queryParameters,
            decoder: decoder,
            interceptors: interceptors
        )
    }
}
