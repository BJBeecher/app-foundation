@preconcurrency import Combine
import Foundation

public actor NavigationRouter<Destination: RouterDestination>: Sendable {
    private let destinationSubject = CurrentValueSubject<[Destination], Never>([])
    private let sheetSubject = CurrentValueSubject<[Destination], Never>([])
    private let alertSubject = CurrentValueSubject<[PopupAlert], Never>([])
    private let loadingSubject = CurrentValueSubject<String?, Never>(nil)

    public init() {}

    public var destinationsStream: AsyncStream<[Destination]> {
        destinationSubject
            .removeDuplicates()
            .vlEraseToStream()
    }

    public var sheetStream: AsyncStream<Destination?> {
        sheetSubject
            .map(\.last)
            .removeDuplicates()
            .vlEraseToStream()
    }

    public var alertStream: AsyncStream<PopupAlert?> {
        alertSubject
            .map(\.last)
            .removeDuplicates()
            .vlEraseToStream()
    }

    public var loadingStream: AsyncStream<String?> {
        loadingSubject
            .removeDuplicates()
            .vlEraseToStream()
    }

    public func updateDestinations(with destinations: [Destination]) {
        destinationSubject.send(destinations)
    }

    public func navigateTo(_ destination: Destination) {
        var destinations = destinationSubject.value
        destinations.append(destination)
        destinationSubject.send(destinations)
    }

    public func reset(root: Destination) {
        destinationSubject.send([root])
    }

    public func resetRouter(root: Destination) {
        reset(root: root)
    }

    public func goBack() {
        var destinations = destinationSubject.value
        guard !destinations.isEmpty else { return }
        destinations.removeLast()
        destinationSubject.send(destinations)
    }

    public func presentSheet(_ destination: Destination) {
        var sheets = sheetSubject.value
        sheets.append(destination)
        sheetSubject.send(sheets)
    }

    public func presentSheet(destination: Destination) {
        presentSheet(destination)
    }

    public func dismissSheet() {
        var sheets = sheetSubject.value
        guard !sheets.isEmpty else { return }
        sheets.removeLast()
        sheetSubject.send(sheets)
    }

    @discardableResult
    public func presentAlert(_ alert: PopupAlert) async -> AlertButton {
        await withCheckedContinuation { continuation in
            var alert = alert
            let state = AlertContinuationState()
            alert.setTappedHandler { button in
                guard state.resume() else { return }

                continuation.resume(returning: button)
            }

            var alerts = alertSubject.value
            alerts.append(alert)
            alertSubject.send(alerts)
        }
    }

    public func dismissAlert() {
        var alerts = alertSubject.value
        guard !alerts.isEmpty else { return }
        let alert = alerts.removeLast()
        alert.tapped?(.dismissed)
        alertSubject.send(alerts)
    }

    public func showLoader(_ message: String?) {
        loadingSubject.send(message ?? "Loading...")
    }

    public func showLoader(message: String?) {
        showLoader(message)
    }

    public func hideLoader() {
        loadingSubject.send(nil)
    }
}

private final class AlertContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isResumed = false

    func resume() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isResumed else { return false }
        isResumed = true
        return true
    }
}

private extension Publisher where Failure == Never, Output: Sendable {
    func vlEraseToStream() -> AsyncStream<Output> {
        AsyncStream { continuation in
            let cancellable = sink { output in
                continuation.yield(output)
            }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}
