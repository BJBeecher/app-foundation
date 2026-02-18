//
//  FileService.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 2/8/25.
//

import Dependencies
import Foundation
import VLSharedModels
import VLCache
import UniformTypeIdentifiers

public protocol FileService: Sendable {
    func createFile(data: Data, contentType: ContentType) async throws -> File
    func delete(file: File) async throws
    func delete(files: [File]) async throws
}

public final class FileServiceLiveValue: FileService, @unchecked Sendable {
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

public final class FileServicePreviewValue: FileService {
    public func createFile(data: Data, contentType: ContentType) async throws -> File { .sample }
    public func delete(file: File) async throws {}
    public func delete(files: [File]) async throws {}
}

// MARK: Dependency

public enum FileServiceKey: DependencyKey {
    public static let liveValue: FileService = FileServiceLiveValue()
    public static let previewValue: FileService = FileServicePreviewValue()
}

public extension DependencyValues {
    var fileService: FileService {
        get { self[FileServiceKey.self] }
        set { self[FileServiceKey.self] = newValue }
    }
}
