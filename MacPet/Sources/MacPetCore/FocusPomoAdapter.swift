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

public protocol FocusPomoAdapter: Sendable {
    func fetchSessions(since: Date) async throws -> [FocusSession]
    func currentSession() async -> LiveFocusSession?
}
