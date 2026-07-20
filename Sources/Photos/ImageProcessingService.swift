import Foundation
import ImageIO
import PhotosUI
import SDWebImageWebPCoder
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VLFiles
import VLSharedModels
import VLUtilities

public protocol ImageProcessingService: Sendable {
    func processImageData(_ data: Data) async throws -> ProcessedImage
    func processImageData(_ data: Data, outputFormat: ImageProcessingOutputFormat) async throws -> ProcessedImage
    func processPickerItem(_ item: PhotosPickerItem) async throws -> ProcessedImage
    func processPickerItem(_ item: PhotosPickerItem, outputFormat: ImageProcessingOutputFormat) async throws -> ProcessedImage
}

public enum ImageProcessingOutputFormat: Sendable {
    case jpeg
    case webP
}

public final class DefaultImageProcessingService: ImageProcessingService, @unchecked Sendable {
    private let fileService: FileService

    private let semaphore = AsyncSemaphore(maxConcurrent: 4)
    private let maxDimension: CGFloat = 1200
    private let compressionQuality: CGFloat = 0.8

    public init(fileService: FileService) {
        self.fileService = fileService
    }
    
    public func processPickerItem(_ item: PhotosPickerItem) async throws -> ProcessedImage {
        try await processPickerItem(item, outputFormat: .jpeg)
    }

    public func processPickerItem(_ item: PhotosPickerItem, outputFormat: ImageProcessingOutputFormat) async throws -> ProcessedImage {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw GenericError(message: "Unable to load transferable of type data")
        }
        
        return try await processImageData(data, outputFormat: outputFormat)
    }

    public func processImageData(_ data: Data) async throws -> ProcessedImage {
        try await processImageData(data, outputFormat: .jpeg)
    }

    public func processImageData(_ data: Data, outputFormat: ImageProcessingOutputFormat) async throws -> ProcessedImage {
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

        let processedData = try makeImageData(from: image, outputFormat: outputFormat)
        let contentType: ContentType = switch outputFormat {
        case .jpeg:
            .jpeg
        case .webP:
            .webP
        }
        let file = try await fileService.createFile(data: processedData, contentType: contentType)

        return ProcessedImage(
            file: file,
            byteSize: processedData.count,
            width: Double(image.width),
            height: Double(image.height),
            metadata: metadata
        )
    }

    private func makeImageData(from image: CGImage, outputFormat: ImageProcessingOutputFormat) throws -> Data {
        switch outputFormat {
        case .jpeg:
            return try makeJPEGData(from: image)
        case .webP:
            return try makeWebPData(from: image)
        }
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

    private func makeWebPData(from image: CGImage) throws -> Data {
        let uiImage = UIImage(cgImage: image)

        guard let webPData = SDImageWebPCoder.shared.encodedData(
            with: uiImage,
            format: .webP,
            options: [.encodeCompressionQuality: compressionQuality]
        ) else {
            throw GenericError(message: "Unable to format image data")
        }

        return webPData
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
