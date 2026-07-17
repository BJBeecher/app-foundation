import Alamofire
import Combine
import Foundation
import Testing
@testable import VLHTTP

private struct TestResponse: Codable, Equatable, Sendable {
    let id: Int
}

private struct TestInterceptor: HTTPServiceRequestInterceptor {
    func intercept<Output: Decodable>(_ request: inout HTTPEndpoint<Output>) async throws {
        request.headers["Authorization"] = "Bearer test-token"
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.withLock { storedValue }
    }

    func set() {
        lock.withLock { storedValue = true }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct HTTPServiceTests {
    private func makeService() -> APIServiceLiveValue {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIServiceLiveValue(session: Session(configuration: configuration))
    }

    @Test
    func callDecodesResponse() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"id":42}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let service = makeService()
        let endpoint = HTTPEndpoint<TestResponse>(url: URL(string: "https://example.com/item")!)

        let output = try await service.call(endpoint: endpoint)

        #expect(output == TestResponse(id: 42))
    }

    @Test
    func callAppliesInterceptors() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"id":1}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let service = makeService()
        let endpoint = HTTPEndpoint<TestResponse>(
            url: URL(string: "https://example.com/item")!,
            interceptors: [TestInterceptor()]
        )

        let output = try await service.call(endpoint: endpoint)

        #expect(output == TestResponse(id: 1))
    }

    @Test
    func callThrowsBadStatusCode() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { MockURLProtocol.handler = nil }

        let service = makeService()
        let endpoint = HTTPEndpoint<TestResponse>(url: URL(string: "https://example.com/item")!)

        do {
            let _: TestResponse = try await service.call(endpoint: endpoint)
            Issue.record("Expected a bad status code error")
        } catch APIServiceFailure.badStatusCode(let statusCode) {
            #expect(statusCode == 422)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func unauthorizedResponsePublishesEvent() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { MockURLProtocol.handler = nil }

        let service = makeService()
        let receivedUnauthorized = LockedFlag()
        let cancellable = service.unauthorizedPublisher.sink { receivedUnauthorized.set() }
        defer { cancellable.cancel() }

        let endpoint = HTTPEndpoint<TestResponse>(url: URL(string: "https://example.com/item")!)
        _ = try? await service.call(endpoint: endpoint)

        #expect(receivedUnauthorized.value)
    }
}
