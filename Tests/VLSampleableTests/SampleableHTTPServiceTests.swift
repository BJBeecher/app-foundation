import Foundation
import Testing
import VLHTTP
import VLSampleable
import VLSharedModels

@Suite("Sampleable HTTP service")
struct SampleableHTTPServiceTests {
    private let service = SampleableHTTPService()
    private let url = URL(string: "https://example.com")!

    @Test("Returns the output sample")
    func returnsSample() async throws {
        let response: SampleResponse = try await service.call(endpoint: HTTPEndpoint(url: url))

        #expect(response == .sample)
    }

    @Test("Supports empty responses")
    func supportsEmptyResponse() async throws {
        let _: EmptyResponse = try await service.call(endpoint: HTTPEndpoint(url: url))
    }

    @Test("Rejects output without a sample")
    func rejectsUnsampleableOutput() async {
        await #expect(throws: SampleableHTTPServiceFailure.unavailableSample("UnsampleableResponse")) {
            let _: UnsampleableResponse = try await service.call(endpoint: HTTPEndpoint(url: url))
        }
    }
}

private struct SampleResponse: Codable, Equatable, Sampleable {
    let value: String

    static let sample = SampleResponse(value: "sample")
}

private struct UnsampleableResponse: Codable {}
