import Foundation

public final class MockFocusPomoAdapter: FocusPomoAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [FocusSession] = []
    private var liveStartedAt: Date?

    public init() {}

    public func fetchSessions(since: Date) async throws -> [FocusSession] {
        snapshot(since: since)
    }

    public func currentSession() async -> LiveFocusSession? {
        liveSnapshot()
    }

    @discardableResult
    public func completePomodoro(at now: Date, durationMinutes: Int = 25) -> FocusSession {
        let session = FocusSession(
            id: UUID().uuidString,
            startedAt: now.addingTimeInterval(TimeInterval(-durationMinutes * 60)),
            endedAt: now
        )
        mutate { sessions.append(session) }
        return session
    }

    public func startFocus(at now: Date) {
        mutate { liveStartedAt = now }
    }

    public func stopFocus(at now: Date) {
        let started = mutate { () -> Date? in
            let started = liveStartedAt
            liveStartedAt = nil
            return started
        }
        guard let started else { return }
        let session = FocusSession(
            id: UUID().uuidString,
            startedAt: started,
            endedAt: now
        )
        mutate { sessions.append(session) }
    }

    private func snapshot(since: Date) -> [FocusSession] {
        mutate { sessions.filter { $0.endedAt >= since } }
    }

    private func liveSnapshot() -> LiveFocusSession? {
        mutate {
            guard let liveStartedAt else { return nil }
            return LiveFocusSession(startedAt: liveStartedAt)
        }
    }

    private func mutate<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
