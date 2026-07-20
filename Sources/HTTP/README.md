# VLHTTP

`VLHTTP` provides a small, typed HTTP API backed by Alamofire. Applications define `HTTPEndpoint` values and use `HTTPService` without importing Alamofire directly.

`VLHTTP` handles transport only. Query caching, retries, and request deduplication belong in `VLQuery`.

## Importing

```swift
import VLHTTP
import VLSharedModels
```

## Defining An Endpoint

The endpoint's generic type is the decoded response type:

```swift
struct User: Codable, Sendable {
    let id: UUID
    let name: String
}

let endpoint = HTTPEndpoint<User>(
    url: URL(string: "https://api.example.com/users/current")!,
    queryParameters: [URLQueryItem(name: "include", value: "profile")]
)
```

JSON request bodies can be passed as `Encodable` values:

```swift
struct UpdateUser: Codable, Sendable {
    let name: String
}

let endpoint = HTTPEndpoint<User>(
    url: URL(string: "https://api.example.com/users/current")!,
    method: .patch,
    body: UpdateUser(name: "Taylor")
)
```

## Sending Requests

Create an `HTTPService` in your app or inject one through your app's own dependency system:

```swift
let apiService: HTTPService = AlamofireHTTPService()

let user: User = try await apiService.call(endpoint: endpoint)
```

`VLHTTP` does not register `HTTPService` with a dependency container. Applications own that wiring.

Raw data and file downloads are also available:

```swift
let data = try await apiService.data(from: url)
let fileURL = try await apiService.download(from: url)
```

## Empty Responses

Use `EmptyResponse` for successful responses without a body:

```swift
let endpoint = HTTPEndpoint<EmptyResponse>(
    url: URL(string: "https://api.example.com/session")!,
    method: .delete
)

try await apiService.call(endpoint: endpoint)
```

## Request Interceptors

Interceptors can asynchronously update an endpoint before its request is created. This is useful for authentication headers and token refresh:

```swift
struct AuthenticationInterceptor: HTTPServiceRequestInterceptor {
    func intercept<Output: Decodable>(
        _ endpoint: inout HTTPEndpoint<Output>
    ) async throws {
        endpoint.headers["Authorization"] = "Bearer \(token)"
    }
}

let endpoint = HTTPEndpoint<User>(
    url: url,
    interceptors: [AuthenticationInterceptor()]
)
```

Interceptors run in the order provided.

## Multipart Uploads

Multipart requests support form fields, JSON values, and files:

```swift
let body = MultipartBody(content: [
    .init(name: "caption", source: .formField("Summer")),
    .init(name: "image", source: .file(imageFile)),
])

let endpoint = HTTPEndpoint<EmptyResponse>(
    url: uploadURL,
    method: .post,
    body: .multipart(body)
)
```

Alamofire creates and streams the multipart request body. `VLHTTP` does not create temporary multipart files.

## Errors And Authorization

Non-2xx responses throw `APIServiceFailure.badStatusCode`:

```swift
do {
    let user: User = try await apiService.call(endpoint: endpoint)
} catch APIServiceFailure.badStatusCode(let statusCode) {
    // Handle the server status code.
}
```

The service also emits through `unauthorizedPublisher` whenever it receives a `401` response:

```swift
for await _ in apiService.unauthorizedPublisher.values {
    // Clear the session or present authentication.
}
```
