//
//  Upload.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 5/4/25.
//

@preconcurrency import Combine
import Foundation
import VLSharedModels

final class UploadTaskDelegate: NSObject, URLSessionTaskDelegate {
    let progressPublisher = PassthroughSubject<TaskProgress, Never>()
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        progressPublisher.send(TaskProgress(completed: Double(totalBytesSent), total: Double(totalBytesExpectedToSend)))
    }
}
