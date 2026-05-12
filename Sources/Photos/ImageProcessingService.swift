import Dependencies
import Foundation
import ImageIO
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import VLFiles
import VLSharedModels
import VLUtilities

public protocol ImageProcessingService: Sendable {
    func processImageData(_ data: Data) async throws -> ProcessedImage
    func processPickerItem(_ item: PhotosPickerItem) async throws -> ProcessedImage
}

public final class ImageProcessingServiceLiveValue: ImageProcessingService, @unchecked Sendable {
    @Dependency(\.fileService) private var fileService

    private let semaphore = AsyncSemaphore(maxConcurrent: 4)
    private let maxDimension: CGFloat = 1200
    private let compressionQuality: CGFloat = 0.8
    
    public func processPickerItem(_ item: PhotosPickerItem) async throws -> ProcessedImage {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw GenericError(message: "Unable to load transferable of type data")
        }
        
        return try await processImageData(data)
    }

    public func processImageData(_ data: Data) async throws -> ProcessedImage {
        await semaphore.acquire()
        defer { Task { await semaphore.release() } }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw GenericError(message: "Data not image")
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let metadata = extractMetadata(from: properties)

        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let longestSide = max(width, height)

        let image: CGImage?
        if longestSide > Double(maxDimension) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        guard let image else {
            throw GenericError(message: "Unable to decode image data")
        }

        let jpegData = try makeJPEGData(from: image)
        let file = try await fileService.createFile(data: jpegData, contentType: .jpeg)

        return ProcessedImage(
            file: file,
            byteSize: jpegData.count,
            width: Double(image.width),
            height: Double(image.height),
            metadata: metadata
        )
    }

    private func makeJPEGData(from image: CGImage) throws -> Data {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw GenericError(message: "Unable to format image data")
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw GenericError(message: "Unable to format image data")
        }

        return data as Data
    }

    private func extractMetadata(from properties: [CFString: Any]?) -> ProcessedImage.Metadata {
        let gpsData = properties?[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let exifData = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let latitudeValue = gpsData?[kCGImagePropertyGPSLatitude] as? Double
        let latitudeRef = gpsData?[kCGImagePropertyGPSLatitudeRef] as? String
        let longitudeValue = gpsData?[kCGImagePropertyGPSLongitude] as? Double
        let longitudeRef = gpsData?[kCGImagePropertyGPSLongitudeRef] as? String
        let altitudeValue = gpsData?[kCGImagePropertyGPSAltitude] as? Double
        let altitudeRef = gpsData?[kCGImagePropertyGPSAltitudeRef] as? Int

        let latitude = latitudeValue.map { latitudeRef == "S" ? -$0 : $0 }
        let longitude = longitudeValue.map { longitudeRef == "W" ? -$0 : $0 }
        let altitude = altitudeValue.map { altitudeRef == 1 ? -$0 : $0 }

        let location: ProcessedImage.Location?
        if let latitude, let longitude {
            location = ProcessedImage.Location(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude
            )
        } else {
            location = nil
        }

        let captureDateString = exifData?[kCGImagePropertyExifDateTimeOriginal] as? String
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current

        return ProcessedImage.Metadata(
            captureDate: captureDateString.flatMap { formatter.date(from: $0) },
            location: location
        )
    }
}

public enum ImageProcessingServiceKey: DependencyKey {
    public static let liveValue: ImageProcessingService = ImageProcessingServiceLiveValue()
}

public extension DependencyValues {
    var imageProcessingService: ImageProcessingService {
        get { self[ImageProcessingServiceKey.self] }
        set { self[ImageProcessingServiceKey.self] = newValue }
    }
}
