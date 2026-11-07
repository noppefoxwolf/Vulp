import Foundation

/// Holds one in-flight image load and resumes every caller waiting for its result.
/// Cancelling a waiter only removes that caller; it does not cancel work that may
/// still be needed by other callers.
actor ImageFetchFlight<Value: Sendable> {
    private var result: Result<Value, Error>?
    private var waiters: [UUID: CheckedContinuation<Value, Error>] = [:]

    func value() async throws -> Value {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
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
    }
}

/// Coalesces simultaneous image loads that use the same key.
///
/// This is separate from the image cache: it only shares work while a load is
/// in progress, then removes the flight after its result has been delivered.
actor ImageFetchDeduper<Value: Sendable> {
    private var flights: [String: ImageFetchFlight<Value>] = [:]

    /// Returns the existing load for `key`, or starts `operation` if none exists.
    func load(
        forKey key: String,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let (flight, isLeader) = join(key)
        if isLeader {
            Task {
                do {
                    await flight.complete(.success(try await operation()))
                } catch {
                    await flight.complete(.failure(error))
                }
                remove(key, flight: flight)
            }
        }
        return try await flight.value()
    }

    private func join(_ key: String) -> (flight: ImageFetchFlight<Value>, isLeader: Bool) {
        if let flight = flights[key] {
            return (flight, false)
        }

        let flight = ImageFetchFlight<Value>()
        flights[key] = flight
        return (flight, true)
    }

    private func remove(_ key: String, flight: ImageFetchFlight<Value>) {
        guard flights[key] === flight else { return }
        flights.removeValue(forKey: key)
    }
}
