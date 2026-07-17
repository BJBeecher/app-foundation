import Foundation
import Testing
@testable import VLQuery

private enum MutationTestError: Error {
    case failed
}

private actor MutationCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

private actor MutationEvents {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private actor MutationGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let continuations = continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

@Test
func testMutationPublishesLifecycleState() async throws {
    let client = QueryClient()
    let gate = MutationGate()
    let mutation: Mutation<Int, Int, Void> = client.createMutation { value in
        await gate.wait()
        return value * 2
    }
    let stream = mutation.observe()
    var iterator = stream.makeAsyncIterator()

    let idle = await iterator.next()
    #expect(idle?.status == .idle)

    let task = Task { try await mutation.mutate(3) }
    let pending = await iterator.next()
    #expect(pending?.status == .pending)
    #expect(pending?.variables == 3)

    await gate.open()
    #expect(try await task.value == 6)

    let success = await iterator.next()
    #expect(success?.status == .success)
    #expect(success?.data == 6)
}

@Test
func testMutationAwaitsCallbacksInOrder() async throws {
    let client = QueryClient()
    let events = MutationEvents()
    let callbackStarted = MutationGate()
    let finishCallback = MutationGate()
    let options = MutationOptions<Int, Int, String>(
        onMutate: { variables in
            await events.append("mutate-\(variables)")
            return "context"
        },
        onSuccess: { value, variables, context in
            await events.append("success-\(value)-\(variables)-\(context ?? "nil")")
            await callbackStarted.open()
            await finishCallback.wait()
        },
        onSettled: { value, error, _, context in
            await events.append("settled-\(value ?? -1)-\(error == nil)-\(context ?? "nil")")
        }
    )
    let mutation = client.createMutation(options: options) { value in value + 1 }

    let task = Task { try await mutation.mutate(4) }
    await callbackStarted.wait()
    #expect(await mutation.snapshot.status == .pending)

    await finishCallback.open()
    #expect(try await task.value == 5)
    #expect(await events.values == [
        "mutate-4",
        "success-5-4-context",
        "settled-5-true-context"
    ])
    #expect(await mutation.snapshot.status == .success)
}

@Test
func testMutationPassesContextToErrorAndSettledCallbacks() async {
    let client = QueryClient()
    let events = MutationEvents()
    let options = MutationOptions<Int, Int, String>(
        onMutate: { _ in "rollback-context" },
        onError: { _, variables, context in
            await events.append("error-\(variables)-\(context ?? "nil")")
        },
        onSettled: { value, error, _, context in
            await events.append("settled-\(value == nil)-\(error != nil)-\(context ?? "nil")")
        }
    )
    let mutation = client.createMutation(options: options) { _ in
        throw MutationTestError.failed
    }

    do {
        let _: Int = try await mutation.mutate(7)
        Issue.record("Expected mutation failure")
    } catch {
        #expect(error is MutationTestError)
    }

    #expect(await events.values == [
        "error-7-rollback-context",
        "settled-true-true-rollback-context"
    ])
    #expect(await mutation.snapshot.status == .failure)
    #expect(await mutation.snapshot.failureCount == 1)
}

@Test
func testMutationsDoNotRetryByDefault() async {
    let client = QueryClient()
    let counter = MutationCounter()
    let mutation: Mutation<Int, Int, Void> = client.createMutation { _ in
        _ = await counter.next()
        throw MutationTestError.failed
    }

    _ = try? await mutation.mutate(1)

    #expect(await counter.value == 1)
    #expect(await mutation.snapshot.failureCount == 1)
}

@Test
func testMutationCanRetryUntilSuccess() async throws {
    let client = QueryClient()
    let counter = MutationCounter()
    let options = MutationOptions<Int, Int, Void>(
        retry: .maxAttempts(2),
        retryDelay: .constant(.zero)
    )
    let mutation = client.createMutation(options: options) { _ in
        let attempt = await counter.next()
        if attempt < 3 {
            throw MutationTestError.failed
        }
        return attempt
    }

    #expect(try await mutation.mutate(1) == 3)
    #expect(await counter.value == 3)
    #expect(await mutation.snapshot.failureCount == 2)
}

@Test
func testMutationUsesClientDefaultOptions() async throws {
    let client = QueryClient(
        defaultMutationOptions: MutationDefaultOptions(
            retry: .maxAttempts(2),
            retryDelay: .constant(.zero)
        )
    )
    let counter = MutationCounter()
    let mutation: Mutation<Int, Int, Void> = client.createMutation { _ in
        let attempt = await counter.next()
        if attempt < 3 {
            throw MutationTestError.failed
        }
        return attempt
    }

    #expect(try await mutation.mutate(1) == 3)
    #expect(await counter.value == 3)
}

@Test
func testMutationOptionsOverrideClientDefaults() async {
    let client = QueryClient(
        defaultMutationOptions: MutationDefaultOptions(
            retry: .maxAttempts(2),
            retryDelay: .constant(.zero)
        )
    )
    let counter = MutationCounter()
    let options = MutationOptions<Int, Int, Void>(retry: .never)
    let mutation = client.createMutation(options: options) { _ in
        _ = await counter.next()
        throw MutationTestError.failed
    }

    _ = try? await mutation.mutate(1)

    #expect(await counter.value == 1)
}

@Test
func testConcurrentMutationsRunIndependentlyAndLatestInvocationOwnsState() async throws {
    let client = QueryClient()
    let counter = MutationCounter()
    let slowStarted = MutationGate()
    let finishSlow = MutationGate()
    let mutation: Mutation<Int, Int, Void> = client.createMutation { value in
        _ = await counter.next()
        if value == 1 {
            await slowStarted.open()
            await finishSlow.wait()
        }
        return value
    }

    let slowTask = Task { try await mutation.mutate(1) }
    await slowStarted.wait()
    let latestTask = Task { try await mutation.mutate(2) }

    #expect(try await latestTask.value == 2)
    await finishSlow.open()
    #expect(try await slowTask.value == 1)

    #expect(await counter.value == 2)
    #expect(await mutation.snapshot.status == .success)
    #expect(await mutation.snapshot.data == 2)
    #expect(await mutation.snapshot.variables == 2)
}

@Test
func testMutationResetReturnsToIdle() async throws {
    let client = QueryClient()
    let mutation: Mutation<Int, Int, Void> = client.createMutation { $0 }

    _ = try await mutation.mutate(9)
    await mutation.reset()

    #expect(await mutation.snapshot.status == .idle)
    #expect(await mutation.snapshot.variables == nil)
    #expect(await mutation.snapshot.data == nil)
    #expect(await mutation.snapshot.error == nil)
}
