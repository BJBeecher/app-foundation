import Observation
import SwiftUI

@propertyWrapper
@MainActor
public struct MutationState<Variables: Sendable, Value: Sendable>: @preconcurrency DynamicProperty {
    @Environment(\.queryClient) private var queryClient
    @State private var storage: MutationStateStorage<Variables, Value>

    public init(_ options: MutationOptions<Variables, Value>) {
        self._storage = State(initialValue: MutationStateStorage(options: options))
    }

    public var wrappedValue: MutationState<Variables, Value> {
        self
    }

    public var snapshot: MutationSnapshot<Variables, Value> {
        MutationSnapshot(
            status: storage.status,
            variables: storage.variables,
            data: storage.data,
            error: storage.error,
            failureCount: storage.failureCount
        )
    }
    public var variables: Variables? { storage.variables }
    public var data: Value? { storage.data }
    public var error: Error? { storage.error }
    public var status: MutationStatus { storage.status }
    public var isPending: Bool { storage.status == .pending }
    public var failureCount: Int { storage.failureCount }

    public mutating func update() {
        storage.bind(client: queryClient)
    }

    @discardableResult
    public func mutate(_ variables: Variables) async throws -> Value {
        try await storage.mutate(variables)
    }

    public func reset() async {
        await storage.reset()
    }
}

public extension MutationState where Variables == Void {
    @discardableResult
    func mutate() async throws -> Value {
        try await mutate(())
    }
}

// Internal rather than private, for the same reason as QueryValueStorage: a generic type
// in another module that stores a MutationState has to build metadata for this class, and
// a private class's metadata accessor is not linkable from outside VLQuery.
@MainActor
@Observable
@usableFromInline
final class MutationStateStorage<Variables: Sendable, Value: Sendable> {
    private(set) var variables: Variables?
    private(set) var data: Value?
    private(set) var error: Error?
    private(set) var status: MutationStatus = .idle
    private(set) var failureCount = 0

    @ObservationIgnored private let options: MutationOptions<Variables, Value>
    @ObservationIgnored private var mutation: Mutation<Variables, Value>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var clientID: ObjectIdentifier?

    init(options: MutationOptions<Variables, Value>) {
        self.options = options
    }

    func bind(client: QueryClient) {
        let clientID = ObjectIdentifier(client)
        guard self.clientID != clientID else { return }

        observationTask?.cancel()

        let mutation = client.createMutation(options)
        self.clientID = clientID
        self.mutation = mutation
        apply(.idle)
        self.observationTask = Task { [weak self] in
            for await snapshot in mutation.observe() {
                guard !Task.isCancelled else { return }
                self?.apply(snapshot)
            }
        }
    }

    func mutate(_ variables: Variables) async throws -> Value {
        guard let mutation else {
            throw MutationStateError.notBound
        }
        return try await mutation.mutate(variables)
    }

    func reset() async {
        await mutation?.reset()
    }

    private func apply(_ snapshot: MutationSnapshot<Variables, Value>) {
        let previousStatus = status
        if status != snapshot.status {
            status = snapshot.status
        }
        if failureCount != snapshot.failureCount {
            failureCount = snapshot.failureCount
        }

        switch snapshot.status {
        case .idle:
            if variables != nil { variables = nil }
            if data != nil { data = nil }
            if error != nil { error = nil }
        case .pending:
            if previousStatus != .pending || snapshot.failureCount == 0 {
                variables = snapshot.variables
            }
            if data != nil { data = nil }
            if error != nil { error = nil }
        case .success:
            data = snapshot.data
            if error != nil { error = nil }
        case .failure:
            if data != nil { data = nil }
            error = snapshot.error
        }
    }

    deinit {
        observationTask?.cancel()
    }
}

public enum MutationStateError: Error, Sendable, Equatable {
    case notBound
}
