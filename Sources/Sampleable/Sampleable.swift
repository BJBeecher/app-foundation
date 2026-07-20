import Foundation
import VLSharedModels

public protocol Sampleable: Sendable {
    static var sample: Self { get }
}

extension Array: Sampleable where Element: Sampleable {
    public static var sample: Self { [.sample] }
}

extension Set: Sampleable where Element: Sampleable {
    public static var sample: Self { [.sample] }
}

extension String: Sampleable {
    public static let sample = "Sample"
}

extension EmptyResponse: Sampleable {
    public static let sample = EmptyResponse()
}
