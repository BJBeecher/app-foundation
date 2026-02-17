//
//  FileRepository.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 2/8/25.
//

import Dependencies
import Foundation
import Models
import UniformTypeIdentifiers

public protocol FileRepository: Sendable {
    func createFile(data: Data, contentType: ContentType) async throws -> File
    func delete(file: File) async throws
    func delete(files: [File]) async throws
}

public final class FileRepositoryLiveValue: FileRepository, @unchecked Sendable {
    @Dependency(\.codableStorageService) private var codableStorageService
    
    private let fileManager = FileManager.default
    private let filesStorageId = "file-metadata"
    
    public func createFile(data: Data, contentType: ContentType) async throws -> File {
        let id = UUID()
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appending(path: id.uuidString)
            .appendingPathExtension(contentType.ext)
        
        guard let url else {
            throw GenericError(message: "Could not create url to save data to.")
        }
        
        try data.write(to: url, options: .atomic)
        let file = File(id: id, url: url, contentType: contentType)
        
        if try await codableStorageService.exists(id: filesStorageId, type: Set<File>.self) {
            try await codableStorageService.update(id: filesStorageId) { (files: inout Set<File>) in
                files.insert(file)
            }
        } else {
            try await codableStorageService.save(Set([file]), id: filesStorageId)
        }
        
        return file
    }
    
    public func delete(file: File) async throws {
        if fileManager.fileExists(atPath: file.url.path) {
            try fileManager.removeItem(at: file.url)
        }
        
        try await codableStorageService.update(id: filesStorageId) { (files: inout Set<File>) in
            files.remove(file)
        }
    }
    
    public func delete(files: [File]) async throws {
        for file in files {
            try await delete(file: file)
        }
    }
}

public final class FileRepositoryPreviewValue: FileRepository {
    public func createFile(data: Data, contentType: ContentType) async throws -> File { .sample }
    public func delete(file: File) async throws {}
    public func delete(files: [File]) async throws {}
}

// MARK: Dependency

public enum FileRepositoryKey: DependencyKey {
    public static let liveValue: FileRepository = FileRepositoryLiveValue()
    public static let previewValue: FileRepository = FileRepositoryPreviewValue()
}

public extension DependencyValues {
    var fileRepository: FileRepository {
        get { self[FileRepositoryKey.self] }
        set { self[FileRepositoryKey.self] = newValue }
    }
}
