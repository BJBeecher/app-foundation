import Testing
import Foundation
import VLHTTP

private struct Output: Decodable {}
private struct Payload: Codable, Equatable {
    let id: Int
    let name: String
}

@Test
func testRequestBuildsMethodHeadersQueryAndBody() throws {
    let endpoint = HTTPEndpoint<Output>(
        url: URL(string: "https://example.com/v1/items")!,
        method: .post,
        body: Payload(id: 7, name: "verity"),
        headers: ["X-Test": "1"],
        queryParameters: [URLQueryItem(name: "page", value: "2")]
    )

    let request = try endpoint.request()

    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://example.com/v1/items?page=2")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "X-Test") == "1")
    #expect(request.value(forHTTPHeaderField: "Timezone") != nil)

    let body = try #require(request.httpBody)
    let decoded = try JSONDecoder().decode(Payload.self, from: body)
    #expect(decoded == Payload(id: 7, name: "verity"))
}

@Test
func testRequestPreservesExistingQueryWhenNoQueryParametersAreProvided() throws {
    let endpoint = HTTPEndpoint<Output>(
        url: URL(string: "https://example.com/upload?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc123")!,
        method: .put
    )

    let request = try endpoint.request()

    #expect(request.url?.absoluteString == "https://example.com/upload?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc123")
}

@Test
func testRequestAppendsQueryParametersToExistingQuery() throws {
    let endpoint = HTTPEndpoint<Output>(
        url: URL(string: "https://example.com/upload?X-Amz-Algorithm=AWS4-HMAC-SHA256")!,
        method: .put,
        queryParameters: [URLQueryItem(name: "partNumber", value: "1")]
    )

    let request = try endpoint.request()

    #expect(request.url?.absoluteString == "https://example.com/upload?X-Amz-Algorithm=AWS4-HMAC-SHA256&partNumber=1")
}

@Test
func testRequestKeyIsStableForEquivalentRequests() {
    let url = URL(string: "https://example.com/v1/items")!

    let first = HTTPEndpoint<Output>(
        url: url,
        method: .get,
        headers: ["A": "1", "B": "2"],
        queryParameters: [URLQueryItem(name: "q", value: "x")]
    )

    let second = HTTPEndpoint<Output>(
        url: url,
        method: .get,
        headers: ["B": "2", "A": "1"],
        queryParameters: [URLQueryItem(name: "q", value: "x")]
    )

    #expect(first.requestKey == second.requestKey)
}

@Test
func testRequestKeyChangesWhenBodyChanges() {
    let url = URL(string: "https://example.com/v1/items")!

    let first = HTTPEndpoint<Output>(url: url, method: .post, body: Payload(id: 1, name: "a"))
    let second = HTTPEndpoint<Output>(url: url, method: .post, body: Payload(id: 2, name: "a"))

    #expect(first.requestKey != second.requestKey)
}
