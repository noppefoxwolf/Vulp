import Foundation

/// Holds one in-flight operation and resumes every caller waiting for its result.
/// Cancelling a waiter preserves shared work while any other caller still waits.
actor TaskFlight<Value: Sendable> {
    private var result: Result<Value, Error>?
    private var waiters: [UUID: CheckedContinuation<Value, Error>] = [:]
    private var operationTask: Task<Void, Never>?
    private var isCancelled = false

    func install(_ operationTask: Task<Void, Never>) {
        self.operationTask = operationTask
        if isCancelled {
            operationTask.cancel()
        }
    }

    func isCancelledFlight() -> Bool {
        isCancelled
    }

    func value() async throws -> Value {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    if waiters.isEmpty, result == nil {
                        isCancelled = true
                        operationTask?.cancel()
                    }
                    continuation.resume(throwing: CancellationError())
                } else if isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    waiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(waiterID) }
        }
    }

    func complete(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        let pending = Array(waiters.values)
        waiters.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume(with: result) }
    }

    private func cancel(_ waiterID: UUID) {
        waiters.removeValue(forKey: waiterID)?.resume(throwing: CancellationError())
        if waiters.isEmpty, result == nil {
            isCancelled = true
            operationTask?.cancel()
        }
    }
}

/// Coalesces simultaneous operations that use the same key.
///
/// It only shares work while an operation is in progress, then removes the
/// flight after its result has been delivered.
actor TaskDeduper<Key: Hashable & Sendable, Value: Sendable> {
    private var flights: [Key: TaskFlight<Value>] = [:]

    /// Returns the existing operation for `key`, or starts one if none exists.
    func load(
        forKey key: Key,
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let (flight, isLeader) = await join(key)
        if isLeader {
            let operationTask = Task(priority: priority) {
                do {
                    await flight.complete(.success(try await operation()))
                } catch {
                    await flight.complete(.failure(error))
                }
                remove(key, flight: flight)
            }
            await flight.install(operationTask)
        }
        return try await flight.value()
    }

    private func join(_ key: Key) async -> (flight: TaskFlight<Value>, isLeader: Bool) {
        if let flight = flights[key] {
            if !(await flight.isCancelledFlight()) {
                return (flight, false)
            }
            flights.removeValue(forKey: key)
        }

        let flight = TaskFlight<Value>()
        flights[key] = flight
        return (flight, true)
    }

    private func remove(_ key: Key, flight: TaskFlight<Value>) {
        guard flights[key] === flight else { return }
        flights.removeValue(forKey: key)
    }
}
