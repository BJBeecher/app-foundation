//
//  DataAccessService.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 3/24/25.
//

import Dependencies
import Foundation
import VLSharedModels
import VLCache
import VLHTTP
import VLLogging

public protocol DataService: Sendable {
    func observe<T: DataAccessObject>(id: String) -> AsyncStream<T>
    @discardableResult
    func load<T: DataAccessObject>(endpoint: DataAccessor<T>, refresh: Bool) async throws -> T
    func loadMore<T: Paginateable>(endpoint: DataAccessor<T>, cursor: String) async throws
    func loadMore<T: Paginateable>(endpoint: DataAccessor<T>, cursor: String, direction: PaginationDirection) async throws
    @discardableResult
    func send<T: DataAccessObject>(endpoint: DataAccessor<T>) async throws -> T
    func updateCache<T: DataAccessObject>(accessor: DataAccessor<T>, update: @Sendable (inout T) -> Void) async throws
    func clearCache<T: DataAccessObject>(accessor: DataAccessor<T>)
}

final class DataServiceLiveValue: DataService, @unchecked Sendable {
    @Dependency(\.codableStorageService) public var codableStorageService
    @Dependency(\.apiService) private var apiService
    @Dependency(\.loggingService) private var loggingService

    private let inFlightRequests = InFlightRequestStore()
    
    func observe<T: DataAccessObject>(id: String) -> AsyncStream<T> {
        codableStorageService.observe(id: id)
    }
    
    func load<T: DataAccessObject>(endpoint: DataAccessor<T>, refresh: Bool = false) async throws -> T {
        let cacheId = endpoint.cacheId
        
        if let cacheId, !refresh {
            let existing: T? = try? await codableStorageService.fetch(id: cacheId)
            
            if let existing {
                return existing
            }
        }
        
        let object = try await send(endpoint: endpoint)
        
        if let cacheId {
            try await codableStorageService.save(object, id: cacheId)
        }
        
        return object
    }
    
    func clearCache<T: DataAccessObject>(accessor: DataAccessor<T>) {
        Task {
            do {
                if let cacheId = accessor.cacheId {
                    try await codableStorageService.clear(id: cacheId, model: T.self)
                }
            } catch {
                loggingService.error(error.localizedDescription)
            }
        }
    }

    func updateCache<T: DataAccessObject>(accessor: DataAccessor<T>, update: @Sendable (inout T) -> Void) async throws {
        guard let cacheId = accessor.cacheId else { return }
        try await codableStorageService.update(id: cacheId, update: update)
    }
    
    func loadMore<T: Paginateable>(endpoint: DataAccessor<T>, cursor: String, direction: PaginationDirection) async throws {
        guard let cacheId = endpoint.cacheId else {
            return
        }
        
        let param = URLQueryItem(name: "cursor", value: cursor)
        var queryParameters = endpoint.endpoint.queryParameters
        queryParameters?.append(param)
        var newEndpoint = endpoint
        newEndpoint.endpoint.queryParameters = queryParameters ?? [param]
        let object = try await send(endpoint: newEndpoint)
        try await codableStorageService.update(id: cacheId) { (cached: inout T) in
            var newObject = object
            switch direction {
            case .append:
                newObject.items = cached.items + object.items
            case .prepend:
                newObject.items = object.items + cached.items
            }
            cached = newObject
        }
    }
    
    func send<T: DataAccessObject>(endpoint: DataAccessor<T>) async throws -> T {
        guard let key = endpoint.endpoint.requestKey else {
            return try await performSend(endpoint: endpoint)
        }
        
        return try await inFlightRequests.run(key: key) {
            try await self.performSend(endpoint: endpoint)
        }
    }
    
    private func performSend<T: Decodable>(endpoint: DataAccessor<T>) async throws -> T {
        let response: T = try await apiService.call(endpoint: endpoint.endpoint)
        
        for action in endpoint.postActions {
            Task(priority: .userInitiated) {
                do {
                    try await action(self)
                } catch {
                    loggingService.error(error.localizedDescription)
                }
            }
        }
        
        return response
    }
}

final class DataServicePreviewValue: DataService {
    func loadMore<T>(endpoint: DataAccessor<T>, cursor: String, direction: PaginationDirection) async throws where T : Paginateable {}
    func updateCache<T>(accessor: DataAccessor<T>, update: @Sendable (inout T) -> Void) async throws where T : DataAccessObject {}
    
    func observe<T: DataAccessObject>(id: String) -> AsyncStream<T> {
        AsyncStream { $0.yield(.sample) }
    }
    
    func load<T: DataAccessObject>(endpoint: DataAccessor<T>, refresh: Bool) async throws -> T {
        .sample
    }
    
    func send<T: Decodable & Sampleable>(endpoint: DataAccessor<T>) async throws -> T {
        .sample
    }
    
    func clearCache<T>(accessor: DataAccessor<T>) where T : DataAccessObject {}
}

public extension DataService {
    func loadMore<T: Paginateable>(endpoint: DataAccessor<T>, cursor: String) async throws {
        try await loadMore(endpoint: endpoint, cursor: cursor, direction: .append)
    }

    func loadMore<T: Paginateable>(endpoint: DataAccessor<T>, cursor: String, direction: PaginationDirection) async throws {
        try await loadMore(endpoint: endpoint, cursor: cursor)
    }
}

public enum DataAccessServiceKey: DependencyKey {
    public static let liveValue: DataService = DataServiceLiveValue()
    public static let previewValue: DataService = DataServicePreviewValue()
}

public extension DependencyValues {
    var dataService: DataService {
        get { self[DataAccessServiceKey.self] }
        set { self[DataAccessServiceKey.self] = newValue }
    }
}
