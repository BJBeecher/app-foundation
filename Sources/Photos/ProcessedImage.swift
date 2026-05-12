import Foundation
import VLFiles

public struct ProcessedImage: Sendable, Hashable, Identifiable {
    public let id = UUID()
    public let file: File
    public let byteSize: Int
    public let width: Double
    public let height: Double
    public let metadata: Metadata
}

public extension ProcessedImage {
    struct Metadata: Sendable, Codable, Hashable {
        public let captureDate: Date?
        public let location: Location?
    }

    struct Location: Sendable, Codable, Hashable {
        public let latitude: Double
        public let longitude: Double
        public let altitude: Double?
    }
}
