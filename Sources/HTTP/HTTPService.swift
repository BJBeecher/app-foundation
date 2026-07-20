//
//  httpService.swift
//  TapTap
//
//  Created by BJ Beecher on 9/18/23.
//

import Alamofire
import Combine
import Foundation
import VLFiles
import VLSharedModels

public enum APIServiceFailure: Error {
    case badStatusCode(Int)
}

public protocol HTTPService: Sendable {
    var unauthorizedPublisher: PassthroughSubject<Void, Never> { get }

    func data(from url: URL) async throws -> Data
    func download(from endpoint: URL) async throws -> URL
    @discardableResult func call<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async throws -> Output
}

public final class AlamofireHTTPService: HTTPService, @unchecked Sendable {
    private let session: Session
    public let unauthorizedPublisher = PassthroughSubject<Void, Never>()
    
    public init(
        session: Session = .default
    ) {
        self.session = session
    }
}

// MARK: Public Methods

public extension AlamofireHTTPService {
    func download(from endpoint: URL) async throws -> URL {
        let response = await session
            .download(endpoint)
            .serializingDownloadedFileURL()
            .response

        try checkForServerError(response: response.response, error: response.error)
        return try response.result.get()
    }
    
    func data(from url: URL) async throws -> Data {
        let response = await session
            .request(url)
            .serializingData()
            .response

        try checkForServerError(response: response.response, error: response.error)
        return try response.result.get()
    }
    
    @discardableResult
    func call<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async throws -> Output {
        let intercepted = try await intercept(endpoint: endpoint)
        let request = try intercepted.request()
        let dataRequest: DataRequest

        switch intercepted.body {
        case .some(.file(let file)):
            dataRequest = session.upload(file.url, with: request)

        case .some(.multipart(let multipart)):
            dataRequest = session.upload(
                multipartFormData: try multipart.formData(),
                with: request
            )

        case .some(.json), .some(.jsonParameters), nil:
            dataRequest = session.request(request)
        }

        let response = await dataRequest.serializingData().response
        try checkForServerError(response: response.response, error: response.error)
        return try handleResponse(data: try response.result.get(), decoder: intercepted.decoder)
    }
}

// MARK: Private methods

private extension AlamofireHTTPService {
    func intercept<T: Decodable>(endpoint:  HTTPEndpoint<T>) async throws -> HTTPEndpoint<T> {
        var new = endpoint
        
        for interceptor in endpoint.interceptors {
            try await interceptor.intercept(&new)
        }
        
        return new
    }
    
    func checkForServerError(response: HTTPURLResponse?, error: AFError?) throws {
        guard let response else {
            if let error {
                throw error
            }

            throw GenericError(message: "http response not in right format")
        }
        
        let statusCode = response.statusCode
        
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
    
    func handleResponse<Output: Decodable>(data: Data, decoder: JSONDecoder) throws -> Output {
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

private extension MultipartBody {
    func formData() throws -> MultipartFormData {
        let formData = MultipartFormData(boundary: boundary)

        for part in content {
            switch part.source {
            case .formField(let value):
                formData.append(Data(value.utf8), withName: part.name)
            case .json(let object, let encoder):
                formData.append(
                    try encoder.encode(object),
                    withName: part.name,
                    mimeType: part.contentType
                )
            case .file(let file):
                formData.append(
                    file.url,
                    withName: part.name,
                    fileName: file.url.lastPathComponent,
                    mimeType: part.contentType
                )
            }
        }

        return formData
    }
}
