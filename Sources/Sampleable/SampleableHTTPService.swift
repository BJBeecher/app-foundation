import Combine
import Foundation
import VLHTTP

public enum SampleableHTTPServiceFailure: Error, Equatable {
    case unsupportedDataRequest(URL)
    case unsupportedDownload(URL)
    case unavailableSample(String)
}

public final class SampleableHTTPService: HTTPService, @unchecked Sendable {
    public let unauthorizedPublisher = PassthroughSubject<Void, Never>()

    public init() {}

    public func data(from url: URL) async throws -> Data {
        throw SampleableHTTPServiceFailure.unsupportedDataRequest(url)
    }

    public func download(from endpoint: URL) async throws -> URL {
        throw SampleableHTTPServiceFailure.unsupportedDownload(endpoint)
    }

    public func call<Output: Decodable>(endpoint: HTTPEndpoint<Output>) async throws -> Output {
        guard let sampleable = Output.self as? any Sampleable.Type,
              let output = sampleable.sample as? Output else {
            throw SampleableHTTPServiceFailure.unavailableSample(String(describing: Output.self))
        }
        return output
    }
}
