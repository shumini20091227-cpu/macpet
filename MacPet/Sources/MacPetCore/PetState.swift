public enum PetState: Equatable, Sendable {
    case rest
    case study
    case eat
}

public struct PetStateMachine: Equatable, Sendable {
    public private(set) var state: PetState
    public private(set) var isLiveSessionActive: Bool

    public init(state: PetState = .rest, isLiveSessionActive: Bool = false) {
        self.state = state
        self.isLiveSessionActive = isLiveSessionActive
    }

    public mutating func setLiveSessionActive(_ active: Bool) {
        isLiveSessionActive = active
        guard state != .eat else { return }
        state = active ? .study : .rest
    }

    public mutating func startEating() {
        state = .eat
    }

    public mutating func finishEating() {
        state = .rest
    }
}
