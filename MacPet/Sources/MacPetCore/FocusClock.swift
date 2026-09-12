import Foundation

public struct FocusSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date

    public init(id: String, startedAt: Date, endedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var durationMinutes: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))
    }
}

public struct LiveFocusSession: Equatable, Sendable {
    public let startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}

public final class FocusClock: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [FocusSession] = []
    private var liveStartedAt: Date?

    public init() {}

    public func sessions(since: Date) -> [FocusSession] {
        mutate { sessions.filter { $0.endedAt >= since } }
    }

    public func currentSession() -> LiveFocusSession? {
        mutate {
            guard let liveStartedAt else { return nil }
            return LiveFocusSession(startedAt: liveStartedAt)
        }
    }

    public func elapsed(at now: Date) -> TimeInterval? {
        guard let live = currentSession() else { return nil }
        return now.timeIntervalSince(live.startedAt)
    }

    public static func elapsedDescription(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            if minutes == 0 {
                return "已专注 \(hours) 小时"
            }
            return "已专注 \(hours) 小时 \(minutes) 分钟"
        }
        if minutes > 0 {
            return "已专注 \(minutes) 分钟"
        }
        return "已专注 \(secs) 秒"
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

    private func mutate<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
