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
    let mutation = client.createMutation(
        MutationOptions { value in
            await gate.wait()
            return value * 2
        }
    )
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
    let options = MutationOptions<Int, Int>(
        onMutate: { variables in
            await events.append("mutate-\(variables)")
            return "on-mutate-result"
        },
        onSuccess: { value, variables, onMutateResult in
            await events.append("success-\(value)-\(variables)-\(onMutateResult ?? "nil")")
            await callbackStarted.open()
            await finishCallback.wait()
        },
        onSettled: { value, error, _, onMutateResult in
            await events.append("settled-\(value ?? -1)-\(error == nil)-\(onMutateResult ?? "nil")")
        },
        mutationFn: { value in value + 1 }
    )
    let mutation = client.createMutation(options)

    let task = Task { try await mutation.mutate(4) }
    await callbackStarted.wait()
    #expect(await mutation.snapshot.status == .pending)

    await finishCallback.open()
    #expect(try await task.value == 5)
    #expect(await events.values == [
        "mutate-4",
        "success-5-4-on-mutate-result",
        "settled-5-true-on-mutate-result"
    ])
    #expect(await mutation.snapshot.status == .success)
}

@Test
func testMutationPassesOnMutateResultToErrorAndSettledCallbacks() async {
    let client = QueryClient()
    let events = MutationEvents()
    let options = MutationOptions<Int, Int>(
        onMutate: { _ in "rollback-context" },
        onError: { _, variables, onMutateResult in
            await events.append("error-\(variables)-\(onMutateResult ?? "nil")")
        },
        onSettled: { value, error, _, onMutateResult in
            await events.append("settled-\(value == nil)-\(error != nil)-\(onMutateResult ?? "nil")")
        },
        mutationFn: { _ in throw MutationTestError.failed }
    )
    let mutation = client.createMutation(options)

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
    let mutation = client.createMutation(
        MutationOptions<Int, Int> { _ in
            _ = await counter.next()
            throw MutationTestError.failed
        }
    )

    _ = try? await mutation.mutate(1)

    #expect(await counter.value == 1)
    #expect(await mutation.snapshot.failureCount == 1)
}

@Test
func testVoidMutationCanRunWithoutVariables() async throws {
    let client = QueryClient()
    let mutation = client.createMutation(MutationOptions<Void, String> { _ in "success" })

    #expect(try await mutation.mutate() == "success")
}

@Test
func testMutationCanRetryUntilSuccess() async throws {
    let client = QueryClient()
    let counter = MutationCounter()
    let options = MutationOptions<Int, Int>(
        retry: .maxAttempts(2),
        retryDelay: .constant(.zero),
        mutationFn: { _ in
            let attempt = await counter.next()
            if attempt < 3 {
                throw MutationTestError.failed
            }
            return attempt
        }
    )
    let mutation = client.createMutation(options)

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
    let mutation = client.createMutation(
        MutationOptions<Int, Int> { _ in
            let attempt = await counter.next()
            if attempt < 3 {
                throw MutationTestError.failed
            }
            return attempt
        }
    )

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
    let options = MutationOptions<Int, Int>(retry: .never) { _ in
        _ = await counter.next()
        throw MutationTestError.failed
    }
    let mutation = client.createMutation(options)

    _ = try? await mutation.mutate(1)

    #expect(await counter.value == 1)
}

@Test
func testConcurrentMutationsRunIndependentlyAndLatestInvocationOwnsState() async throws {
    let client = QueryClient()
    let counter = MutationCounter()
    let slowStarted = MutationGate()
    let finishSlow = MutationGate()
    let mutation = client.createMutation(
        MutationOptions { value in
            _ = await counter.next()
            if value == 1 {
                await slowStarted.open()
                await finishSlow.wait()
            }
            return value
        }
    )

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
    let mutation = client.createMutation(MutationOptions<Int, Int> { $0 })

    _ = try await mutation.mutate(9)
    await mutation.reset()

    #expect(await mutation.snapshot.status == .idle)
    #expect(await mutation.snapshot.variables == nil)
    #expect(await mutation.snapshot.data == nil)
    #expect(await mutation.snapshot.error == nil)
}
