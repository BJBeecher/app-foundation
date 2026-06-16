//
//  httpService.swift
//  TapTap
//
//  Created by BJ Beecher on 9/18/23.
//

import Combine
import Dependencies
import VLExtensions
import Foundation
import VLSharedModels
import VLFiles
import VLLogging

public enum APIServiceFailure: Error {
    case badStatusCode(Int)
}

public protocol HTTPService: Sendable {
    var unauthorizedPublisher: PassthroughSubject<Void, Never> { get }
    
    func callLoadState<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async -> LoadState<Output>
    
    func data(from url: URL) async throws -> Data
    func download(from endpoint: URL) async throws -> URL
    @discardableResult func call<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async throws -> Output
}

public final class APIServiceLiveValue: HTTPService, @unchecked Sendable {
    @Dependency(\.fileService) private var fileService
    
    private let session: URLSession
    public let unauthorizedPublisher = PassthroughSubject<Void, Never>()
    
    init(
        session: URLSession = .shared
    ) {
        self.session = session
    }
}

// MARK: Public Methods

public extension APIServiceLiveValue {
    func download(from endpoint: URL) async throws -> URL {
        let request = URLRequest(url: endpoint)
        let (url, response) = try await session.download(for: request)
        try checkForServerError(response: response)
        return url
    }
    
    func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try checkForServerError(response: response)
        return data
    }
    
    func callLoadState<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async -> LoadState<Output> {
        do {
            let output: Output = try await call(endpoint: endpoint)
            return .success(output)
        } catch {
            return .failure(error)
        }
    }
    
    @discardableResult
    func call<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async throws -> Output {
        let intercepted = try await intercept(endpoint: endpoint)
        let request = try request(for: intercepted)

        switch intercepted.body {
        case .some(.file(let file)):
            let (data, response) = try await session.upload(for: request, fromFile: file.url)
            return try handleResponse(data: data, response: response, decoder: endpoint.decoder)

        case .some(.multipart(let multipart)):
            let multipartFile = try await multipart.makeBodyFile()

            do {
                let (data, response) = try await session.upload(for: request, fromFile: multipartFile.url)
                try await fileService.delete(file: multipartFile)
                return try handleResponse(data: data, response: response, decoder: endpoint.decoder)
            } catch {
                try? await fileService.delete(file: multipartFile)
                throw error
            }

        case .some(.json), .some(.jsonParameters), nil:
            let (data, response) = try await session.data(for: request)
            return try handleResponse(data: data, response: response, decoder: endpoint.decoder)
        }
    }
}

// MARK: Private methods

private extension APIServiceLiveValue {
    func request<Output: Decodable>(for endpoint: HTTPEndpoint<Output>) throws -> URLRequest {
        guard let url = endpoint.requestURL else {
            throw GenericError(message: "Bad endpoint url: \(endpoint.url)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.value

        for header in endpoint.headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        if let body = endpoint.body {
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
                request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
            }
        }

        return request
    }

    func intercept<T: Decodable>(endpoint:  HTTPEndpoint<T>) async throws -> HTTPEndpoint<T> {
        var new = endpoint
        
        for inteceptor in endpoint.intecepters {
            try await inteceptor.intercept(&new)
        }
        
        return new
    }
    
    func checkForServerError(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenericError(message: "http response not in right format")
        }
        
        let statusCode = httpResponse.statusCode
        
        if statusCode == 401 {
            unauthorizedPublisher.send()
        }
        
        switch statusCode {
        case 200...299:
            return
        default:
            throw APIServiceFailure.badStatusCode(statusCode)
        }
    }
    
    func handleResponse<Output: Decodable>(data: Data, response: URLResponse, decoder: JSONDecoder) throws -> Output {
        try checkForServerError(response: response)
        
        if Output.self == EmptyResponse.self {
            return EmptyResponse() as! Output
        } else if Output.self == AttributedString.self {
            let string = try AttributedString(markdown: data, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return string as! Output
        } else {
            return try decoder.decode(Output.self, from: data)
        }
    }
}

// MARK: Preview

final class APIServicePreviewValue: HTTPService, @unchecked Sendable {
    func data(from url: URL) async throws -> Data {
        throw GenericError(message: "Not in use")
    }
    
    let unauthorizedPublisher = PassthroughSubject<Void, Never>()
    
    func download(from endpoint: URL) async throws -> URL {
        throw GenericError(message: "Not in use")
    }
    
    func callLoadState<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async -> LoadState<Output> { .loading }
    
    func call<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async throws -> Output {
        throw GenericError(message: "Not in use")
    }
}

// MARK: Dependency

public enum APIServiceKey: DependencyKey {
    public static let liveValue: HTTPService = APIServiceLiveValue()
    public static let previewValue: HTTPService = APIServicePreviewValue()
}

public extension DependencyValues {
    var apiService: HTTPService {
        get { self[APIServiceKey.self] }
        set { self[APIServiceKey.self] = newValue }
    }
}
