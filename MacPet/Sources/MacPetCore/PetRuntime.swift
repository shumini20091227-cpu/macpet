import CoreGraphics
import Foundation

public final class PetRuntime: @unchecked Sendable {
    public private(set) var petState: PetState
    public private(set) var foodCount: Int
    public private(set) var isFocusing: Bool = false
    public private(set) var eatStartedAt: Date?
    public var onChange: (@Sendable () -> Void)?

    public let settings: AppSettings
    public var windowOrigin: CGPoint? {
        get { store.windowOrigin }
        set { store.windowOrigin = newValue }
    }
    public var isWindowHidden: Bool {
        get { store.isWindowHidden }
        set { store.isWindowHidden = newValue }
    }
    public var petSize: CGFloat {
        get { store.petSize }
        set { store.petSize = newValue }
    }
    public var leftGlint: CGPoint {
        get { store.leftGlint }
        set { store.leftGlint = newValue }
    }
    public var rightGlint: CGPoint {
        get { store.rightGlint }
        set { store.rightGlint = newValue }
    }

    public func resetGlints() {
        store.resetGlints()
    }

    private let store: AppStore
    private let focus: FocusClock
    private let browser: BrowserOpening
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let calendar: Calendar
    private var engine: FoodEngine
    private var machine: PetStateMachine
    private var ledger: FoodLedger
    private var eatTask: Task<Void, Never>?

    public init(
        store: AppStore,
        focus: FocusClock = FocusClock(),
        settings: AppSettings = AppSettings(),
        browser: BrowserOpening,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { duration in
            try? await Task.sleep(for: .seconds(duration))
        }
    ) {
        self.store = store
        self.focus = focus
        self.settings = settings
        self.browser = browser
        self.calendar = calendar
        self.now = now
        self.sleep = sleep
        self.engine = FoodEngine(settings: settings)
        self.machine = PetStateMachine()
        self.ledger = store.ledger
        self.petState = machine.state
        self.foodCount = ledger.foodCount
    }

    public func refreshFocus() {
        let previousFood = foodCount
        let previousState = petState
        let previousFocusing = isFocusing

        let sessions = focus.sessions(since: .distantPast)
        let next = engine.apply(sessions: sessions, ledger: ledger, now: now(), calendar: calendar)
        if next != ledger {
            ledger = next
            store.save(ledger: ledger)
            foodCount = ledger.foodCount
        }

        let live = focus.currentSession()
        isFocusing = live != nil
        machine.setLiveSessionActive(live != nil)
        petState = machine.state
        if foodCount != previousFood || petState != previousState || isFocusing != previousFocusing {
            notify()
        }
    }

    public func completePomodoro() {
        focus.completePomodoro(at: now())
        refreshFocus()
    }

    public func toggleFocus() {
        if isFocusing {
            focus.stopFocus(at: now())
        } else {
            focus.startFocus(at: now())
        }
        refreshFocus()
    }

    public func focusDurationText() -> String? {
        guard let elapsed = focus.elapsed(at: now()) else { return nil }
        return FocusClock.elapsedDescription(seconds: elapsed)
    }

    @discardableResult
    public func feed() -> Bool {
        guard machine.state != .eat else { return false }
        guard engine.consumeFood(&ledger) else { return false }
        store.save(ledger: ledger)
        foodCount = ledger.foodCount
        machine.startEating()
        petState = machine.state
        eatStartedAt = now()
        eatTask?.cancel()
        notify()
        eatTask = Task { [sleep, duration = settings.eatAnimationDuration] in
            await sleep(duration)
            guard !Task.isCancelled else { return }
            self.finishEating()
        }
        return true
    }

    public func waitForEatToFinish() async {
        await eatTask?.value
    }

    public func handleLeftClick() {
        ChatGPTOpener().open(using: browser)
    }

    public func persistWindowOrigin(_ origin: CGPoint) {
        store.windowOrigin = origin
    }

    public func hideWindow() {
        store.isWindowHidden = true
    }

    public func showWindow() {
        store.isWindowHidden = false
    }

    private func finishEating() {
        machine.finishEating()
        petState = machine.state
        eatStartedAt = nil
        if isFocusing {
            machine.setLiveSessionActive(true)
            petState = machine.state
        }
        notify()
    }

    private func notify() {
        onChange?()
    }
}
