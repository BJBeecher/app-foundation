# VLSampleable

`VLSampleable` defines sample data independently from persistence and provides an `HTTPService` for previews.

## Defining Samples

Conform response models to `Sampleable`:

```swift
import VLSampleable

struct User: Codable, Sendable, Sampleable {
    let id: UUID
    let name: String

    static let sample = User(id: UUID(), name: "Sample User")
}
```

`Array`, `Set`, `String`, and `EmptyResponse` include sample implementations.

## Preview HTTP

`SampleableHTTPService` returns the endpoint output's static sample without performing a network request:

```swift
let service = SampleableHTTPService()
let user: User = try await service.call(endpoint: endpoint)
```

The service throws `SampleableHTTPServiceFailure.unavailableSample` when an endpoint output does not conform to `Sampleable`. Raw data and download requests are unsupported because they do not declare an output model.
