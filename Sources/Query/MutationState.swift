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

    public var snapshot: MutationSnapshot<Variables, Value> { storage.snapshot }
    public var variables: Variables? { snapshot.variables }
    public var data: Value? { snapshot.data }
    public var error: Error? { snapshot.error }
    public var status: MutationStatus { snapshot.status }
    public var isPending: Bool { snapshot.isPending }
    public var failureCount: Int { snapshot.failureCount }

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

@MainActor
@Observable
private final class MutationStateStorage<Variables: Sendable, Value: Sendable> {
    private(set) var snapshot: MutationSnapshot<Variables, Value> = .idle

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
        self.snapshot = .idle
        self.observationTask = Task { [weak self] in
            for await snapshot in mutation.observe() {
                guard !Task.isCancelled else { return }
                self?.snapshot = snapshot
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

    deinit {
        observationTask?.cancel()
    }
}

public enum MutationStateError: Error, Sendable, Equatable {
    case notBound
}
