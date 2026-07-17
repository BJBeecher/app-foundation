public struct MutationSnapshot<Variables: Sendable, Value: Sendable>: Sendable {
    public var status: MutationStatus
    public var variables: Variables?
    public var data: Value?
    public var error: Error?
    public var failureCount: Int

    public var isPending: Bool { status == .pending }

    public init(
        status: MutationStatus,
        variables: Variables?,
        data: Value?,
        error: Error?,
        failureCount: Int
    ) {
        self.status = status
        self.variables = variables
        self.data = data
        self.error = error
        self.failureCount = failureCount
    }

    public static var idle: Self {
        MutationSnapshot(
            status: .idle,
            variables: nil,
            data: nil,
            error: nil,
            failureCount: 0
        )
    }
}

public enum MutationStatus: Sendable, Equatable {
    case idle
    case pending
    case success
    case failure
}
