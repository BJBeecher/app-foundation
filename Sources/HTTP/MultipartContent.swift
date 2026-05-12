//
//  MultipartContent.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 5/19/25.
//

import Dependencies
import Foundation
import VLFiles

public struct MultipartBody: Sendable {
    @Dependency(\.fileService) private var fileService
    
    public let content: [Content]
    public let boundary: String

    public init(content: [Content], boundary: String = UUID().uuidString) {
        self.content = content
        self.boundary = boundary
    }
    
    func makeBodyFile() async throws -> File {
        let bodyFile = try await fileService.createFile(data: Data(), contentType: .multipart)
        let fileHandle = try FileHandle(forUpdating: bodyFile.url)

        do {
            for part in content {
                try write(part, to: fileHandle)
            }

            if let closing = "--\(boundary)--\r\n".data(using: .utf8) {
                try fileHandle.write(contentsOf: closing)
            }

            try fileHandle.close()
            return bodyFile
        } catch {
            try? fileHandle.close()
            try? await fileService.delete(file: bodyFile)
            throw error
        }
    }

    private func write(_ part: Content, to fileHandle: FileHandle) throws {
        switch part.source {
        case .formField(let value):
            try writeFormField(name: part.name, value: value, to: fileHandle)
        case .json(let object, let encoder):
            try writeDataField(
                name: part.name,
                contentType: part.contentType,
                data: encoder.encode(object),
                to: fileHandle
            )
        case .file(let file):
            try writeFileField(name: part.name, file: file, to: fileHandle)
        }
    }

    private func writeFormField(name: String, value: String, to fileHandle: FileHandle) throws {
        var header = ""
        header.append("--\(boundary)\r\n")
        header.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        header.append("\(value)\r\n")

        if let data = header.data(using: .utf8) {
            try fileHandle.write(contentsOf: data)
        }
    }

    private func writeDataField(name: String, contentType: String, data: Data, to fileHandle: FileHandle) throws {
        var header = ""
        header.append("--\(boundary)\r\n")
        header.append("Content-Disposition: form-data; name=\"\(name)\"\r\n")
        header.append("Content-Type: \(contentType)\r\n\r\n")

        if let headerData = header.data(using: .utf8) {
            try fileHandle.write(contentsOf: headerData)
        }

        try fileHandle.write(contentsOf: data)
        try writeLineBreak(to: fileHandle)
    }

    private func writeFileField(name: String, file: File, to fileHandle: FileHandle) throws {
        var header = ""
        header.append("--\(boundary)\r\n")
        header.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(file.url.lastPathComponent)\"\r\n")
        header.append("Content-Type: \(file.contentType.headerValue)\r\n\r\n")

        if let headerData = header.data(using: .utf8) {
            try fileHandle.write(contentsOf: headerData)
        }

        try fileHandle.write(contentsOf: Data(contentsOf: file.url))
        try writeLineBreak(to: fileHandle)
    }

    private func writeLineBreak(to fileHandle: FileHandle) throws {
        if let lineBreak = "\r\n".data(using: .utf8) {
            try fileHandle.write(contentsOf: lineBreak)
        }
    }
}

extension MultipartBody {
    public struct Content: Sendable {
        public let name: String
        public let source: MultipartContentSource
        
        public init(
            name: String,
            source: MultipartContentSource
        ) {
            self.name = name
            self.source = source
        }
        
        public var contentType: String {
            switch source {
            case .formField:
                "text/plain"
            case .json:
                "application/json"
            case .file(let file):
                file.contentType.headerValue
            }
        }
    }
    
    public enum MultipartContentSource: Sendable {
        case formField(String)
        case json(any Encodable & Sendable, encoder: JSONEncoder = .init())
        case file(File)
    }
}
