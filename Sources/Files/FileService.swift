//
//  FileService.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 2/8/25.
//

import Foundation
import VLSharedModels
import VLCache
import UniformTypeIdentifiers

public protocol FileService: Sendable {
    func createFile(data: Data, contentType: ContentType) async throws -> File
    func delete(file: File) async throws
    func delete(files: [File]) async throws
}

public final class LocalFileService: FileService, @unchecked Sendable {
    private let codableStorageService: CodableCacheService
    
    private let fileManager = FileManager.default
    private let filesStorageId = "file-metadata"

    public init(codableStorageService: CodableCacheService) {
        self.codableStorageService = codableStorageService
    }
    
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
        
        if try await codableStorageService.contains(key: filesStorageId) {
            try await codableStorageService.update(key: filesStorageId) { (files: inout Set<File>) in
                files.insert(file)
            }
        } else {
            try await codableStorageService.save(Set([file]), key: filesStorageId)
        }
        
        return file
    }
    
    public func delete(file: File) async throws {
        if fileManager.fileExists(atPath: file.url.path) {
            try fileManager.removeItem(at: file.url)
        }
        
        try await codableStorageService.update(key: filesStorageId) { (files: inout Set<File>) in
            files.remove(file)
        }
    }
    
    public func delete(files: [File]) async throws {
        for file in files {
            try await delete(file: file)
        }
    }
}
