import CoreGraphics
import Foundation
import MacPetCore

enum FoodEngineSuite {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let day = Date(timeIntervalSince1970: 1_700_000_000)
    private static let engine = FoodEngine(settings: AppSettings())

    private static func session(id: String, minutes: Int, endingAt end: Date) -> FocusSession {
        FocusSession(
            id: id,
            startedAt: end.addingTimeInterval(TimeInterval(-minutes * 60)),
            endedAt: end
        )
    }

    private static func emptyLedger(at now: Date) -> FoodLedger {
        FoodLedger(
            foodCount: 0,
            rewardedSessionIDs: [],
            foodsGrantedOnDay: 0,
            grantDay: calendar.startOfDay(for: now)
        )
    }

    static func twentyFiveMinutesGrantsOneFood() async throws {
        let result = engine.apply(
            sessions: [session(id: "a", minutes: 25, endingAt: day)],
            ledger: emptyLedger(at: day),
            now: day,
            calendar: calendar
        )
        try expectEqual(result.foodCount, 1)
        try expectEqual(result.rewardedSessionIDs, ["a"])
        try expectEqual(result.foodsGrantedOnDay, 1)
    }

    static func fortyNineMinutesGrantsOneFood() async throws {
        let result = engine.apply(
            sessions: [session(id: "b", minutes: 49, endingAt: day)],
            ledger: emptyLedger(at: day),
            now: day,
            calendar: calendar
        )
        try expectEqual(result.foodCount, 1)
    }

    static func fiftyMinutesGrantsTwoFoods() async throws {
        let result = engine.apply(
            sessions: [session(id: "c", minutes: 50, endingAt: day)],
            ledger: emptyLedger(at: day),
            now: day,
            calendar: calendar
        )
        try expectEqual(result.foodCount, 2)
        try expectEqual(result.foodsGrantedOnDay, 2)
    }

    static func sessionShorterThanMinimumGrantsNothing() async throws {
        let result = engine.apply(
            sessions: [session(id: "d", minutes: 4, endingAt: day)],
            ledger: emptyLedger(at: day),
            now: day,
            calendar: calendar
        )
        try expectEqual(result.foodCount, 0)
        try expect(result.rewardedSessionIDs.isEmpty)
    }

    static func duplicateSessionIsNotRewardedTwice() async throws {
        let sessions = [session(id: "a", minutes: 25, endingAt: day)]
        let first = engine.apply(sessions: sessions, ledger: emptyLedger(at: day), now: day, calendar: calendar)
        let second = engine.apply(sessions: sessions, ledger: first, now: day, calendar: calendar)
        try expectEqual(second.foodCount, 1)
        try expectEqual(second.foodsGrantedOnDay, 1)
    }

    static func dailyCapBlocksAdditionalFood() async throws {
        var ledger = emptyLedger(at: day)
        for index in 1...12 {
            ledger = engine.apply(
                sessions: [session(id: "s\(index)", minutes: 25, endingAt: day)],
                ledger: ledger,
                now: day,
                calendar: calendar
            )
        }
        try expectEqual(ledger.foodCount, 12)
        let extra = engine.apply(
            sessions: [session(id: "s13", minutes: 25, endingAt: day)],
            ledger: ledger,
            now: day,
            calendar: calendar
        )
        try expectEqual(extra.foodCount, 12)
        try expect(extra.rewardedSessionIDs.contains("s13"))
        try expectEqual(extra.foodsGrantedOnDay, 12)
    }

    static func newDayResetsDailyCapButKeepsFood() async throws {
        var ledger = emptyLedger(at: day)
        ledger.foodCount = 3
        ledger.foodsGrantedOnDay = 12
        ledger.rewardedSessionIDs = ["old"]
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let result = engine.apply(
            sessions: [session(id: "next", minutes: 25, endingAt: nextDay)],
            ledger: ledger,
            now: nextDay,
            calendar: calendar
        )
        try expectEqual(result.foodCount, 4)
        try expectEqual(result.foodsGrantedOnDay, 1)
        try expectEqual(result.grantDay, calendar.startOfDay(for: nextDay))
    }

    static func feedDeductsOneFood() async throws {
        var ledger = emptyLedger(at: day)
        ledger.foodCount = 2
        try expect(engine.consumeFood(&ledger))
        try expectEqual(ledger.foodCount, 1)
    }

    static func feedFailsWhenEmpty() async throws {
        var ledger = emptyLedger(at: day)
        try expect(!engine.consumeFood(&ledger))
        try expectEqual(ledger.foodCount, 0)
    }
}

enum PetStateMachineSuite {
    static func startsInRest() async throws {
        try expectEqual(PetStateMachine().state, .rest)
    }

    static func liveSessionMovesToStudy() async throws {
        var machine = PetStateMachine()
        machine.setLiveSessionActive(true)
        try expectEqual(machine.state, .study)
    }

    static func endingLiveSessionReturnsToRest() async throws {
        var machine = PetStateMachine()
        machine.setLiveSessionActive(true)
        machine.setLiveSessionActive(false)
        try expectEqual(machine.state, .rest)
    }

    static func startEatingMovesToEatFromRestOrStudy() async throws {
        var machine = PetStateMachine()
        machine.startEating()
        try expectEqual(machine.state, .eat)

        machine = PetStateMachine()
        machine.setLiveSessionActive(true)
        machine.startEating()
        try expectEqual(machine.state, .eat)
    }

    static func liveSessionDoesNotLeaveEatUntilFinished() async throws {
        var machine = PetStateMachine()
        machine.startEating()
        machine.setLiveSessionActive(true)
        try expectEqual(machine.state, .eat)
        machine.setLiveSessionActive(false)
        try expectEqual(machine.state, .eat)
    }

    static func finishEatingReturnsToRest() async throws {
        var machine = PetStateMachine()
        machine.setLiveSessionActive(true)
        machine.startEating()
        machine.finishEating()
        try expectEqual(machine.state, .rest)
    }
}

enum PetGestureSuite {
    static func zeroMovementIsClick() async throws {
        try expectEqual(classifyPetGesture(translation: .zero, threshold: 5), .click)
    }

    static func movementAtOrBelowThresholdIsClick() async throws {
        try expectEqual(classifyPetGesture(translation: CGSize(width: 3, height: 4), threshold: 5), .click)
        try expectEqual(classifyPetGesture(translation: CGSize(width: 5, height: 0), threshold: 5), .click)
    }

    static func movementBeyondThresholdIsDrag() async throws {
        try expectEqual(classifyPetGesture(translation: CGSize(width: 5.1, height: 0), threshold: 5), .drag)
        try expectEqual(classifyPetGesture(translation: CGSize(width: 4, height: 4), threshold: 5), .drag)
    }
}

enum MockAdapterSuite {
    static func completePomodoroCreatesTwentyFiveMinuteSession() async throws {
        let adapter = MockFocusPomoAdapter()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = adapter.completePomodoro(at: now)
        try expectEqual(session.durationMinutes, 25)
        try expectEqual(session.endedAt, now)
        let fetched = try await adapter.fetchSessions(since: .distantPast)
        try expectEqual(fetched.map(\.id), [session.id])
        try expect(await adapter.currentSession() == nil)
    }

    static func startAndStopFocusTracksLiveSession() async throws {
        let adapter = MockFocusPomoAdapter()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        adapter.startFocus(at: start)
        try expectEqual(await adapter.currentSession()?.startedAt, start)
        let end = start.addingTimeInterval(25 * 60)
        adapter.stopFocus(at: end)
        try expect(await adapter.currentSession() == nil)
        let fetched = try await adapter.fetchSessions(since: .distantPast)
        try expectEqual(fetched.count, 1)
        try expectEqual(fetched[0].durationMinutes, 25)
    }
}

enum AppStoreSuite {
    private static func makeStore() -> AppStore {
        let suite = "MacPetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppStore(defaults: defaults)
    }

    static func persistsFoodLedgerAndWindow() async throws {
        let store = makeStore()
        let ledger = FoodLedger(
            foodCount: 4,
            rewardedSessionIDs: ["one", "two"],
            foodsGrantedOnDay: 2,
            grantDay: Date(timeIntervalSince1970: 1_700_000_000)
        )
        store.save(ledger: ledger)
        store.windowOrigin = CGPoint(x: 120, y: 80)
        store.isWindowHidden = true
        try expectEqual(store.ledger.foodCount, 4)
        try expectEqual(store.ledger.rewardedSessionIDs, ["one", "two"])
        try expectEqual(store.ledger.foodsGrantedOnDay, 2)
        try expectEqual(store.windowOrigin, CGPoint(x: 120, y: 80))
        try expect(store.isWindowHidden)
        store.petSize = 300
        try expectClose(Double(store.petSize), 300)
        store.leftGlint = CGPoint(x: 0.40, y: 0.55)
        store.rightGlint = CGPoint(x: 0.62, y: 0.54)
        try expectClose(Double(store.leftGlint.x), 0.40)
        try expectClose(Double(store.rightGlint.x), 0.62)
    }

    static func defaultLedgerIsEmpty() async throws {
        let store = makeStore()
        try expectEqual(store.ledger.foodCount, 0)
        try expect(store.ledger.rewardedSessionIDs.isEmpty)
        try expect(store.windowOrigin == nil)
        try expect(!store.isWindowHidden)
        try expectClose(Double(store.petSize), Double(PetSizing.defaultSize))
        try expectClose(Double(store.leftGlint.x), Double(PetMotion.leftEyeCenter.x))
        try expectClose(Double(store.rightGlint.x), Double(PetMotion.rightEyeCenter.x))
    }
}

enum PetSizingSuite {
    static func clampsSizeToAllowedRange() async throws {
        try expectClose(Double(PetSizing.clamp(10)), Double(PetSizing.minSize))
        try expectClose(Double(PetSizing.clamp(900)), Double(PetSizing.maxSize))
        try expectClose(Double(PetSizing.clamp(220)), 220)
    }

    static func cornerDragGrowsAndShrinks() async throws {
        let grown = PetSizing.size(original: 220, translation: CGSize(width: 20, height: 20), handle: .topRight)
        let shrunk = PetSizing.size(original: 220, translation: CGSize(width: -20, height: -20), handle: .topRight)
        let bottomRight = PetSizing.size(original: 220, translation: CGSize(width: 20, height: -20), handle: .bottomRight)
        try expect(grown > 220)
        try expect(shrunk < 220)
        try expectClose(Double(grown), Double(bottomRight))
    }

    static func windowGrowsWhenResizing() async throws {
        try expectClose(Double(PetSizing.windowLength(petSize: 220, isResizing: false)), 220)
        try expect(PetSizing.windowLength(petSize: 220, isResizing: true) > 220)
        try expect(PetSizing.handle(at: CGPoint(x: PetSizing.chromePadding, y: PetSizing.chromePadding + 220), petSize: 220) == .topLeft)
        try expect(PetSizing.handle(at: CGPoint(x: 110, y: 110), petSize: 220) == nil)
    }
}

private final class RecordingBrowser: BrowserOpening, @unchecked Sendable {
    var opened: [URL] = []
    func open(_ url: URL) {
        opened.append(url)
    }
}

enum ChatGPTSuite {
    static func opensWebChatGPT() async throws {
        let browser = RecordingBrowser()
        ChatGPTOpener().open(using: browser)
        try expectEqual(browser.opened, [ChatGPTOpener.url])
        try expectEqual(ChatGPTOpener.url.absoluteString, "https://chatgpt.com")
    }
}

enum PetRuntimeSuite {
    private static func makeRuntime(
        browser: RecordingBrowser = RecordingBrowser(),
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { _ in }
    ) -> (PetRuntime, MockFocusPomoAdapter, RecordingBrowser) {
        let suite = "MacPetRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let adapter = MockFocusPomoAdapter()
        let runtime = PetRuntime(
            store: AppStore(defaults: defaults),
            adapter: adapter,
            mock: adapter,
            settings: AppSettings(),
            browser: browser,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: sleep
        )
        return (runtime, adapter, browser)
    }

    static func completingMockPomodoroAddsFood() async throws {
        let (runtime, _, _) = makeRuntime()
        runtime.completeMockPomodoro()
        await runtime.syncFromAdapter()
        try expectEqual(runtime.foodCount, 1)
        try expectEqual(runtime.petState, .rest)
    }

    static func feedingConsumesFoodAndPlaysEatThenRest() async throws {
        let (runtime, _, _) = makeRuntime()
        runtime.completeMockPomodoro()
        await runtime.syncFromAdapter()
        try expect(runtime.feed())
        try expectEqual(runtime.foodCount, 0)
        try expectEqual(runtime.petState, .eat)
        await runtime.waitForEatToFinish()
        try expectEqual(runtime.petState, .rest)
    }

    static func feedFailsWithoutFood() async throws {
        let (runtime, _, _) = makeRuntime()
        try expect(!runtime.feed())
        try expectEqual(runtime.petState, .rest)
    }

    static func liveFocusMovesPetToStudy() async throws {
        let (runtime, adapter, _) = makeRuntime()
        adapter.startFocus(at: Date(timeIntervalSince1970: 1_700_000_000))
        await runtime.syncFromAdapter()
        try expectEqual(runtime.petState, .study)
    }

    static func leftClickOpensChatGPT() async throws {
        let browser = RecordingBrowser()
        let (runtime, _, _) = makeRuntime(browser: browser)
        runtime.handleLeftClick()
        try expectEqual(browser.opened, [ChatGPTOpener.url])
    }

    static func feedRecordsEatStartTime() async throws {
        let (runtime, _, _) = makeRuntime()
        try expect(runtime.eatStartedAt == nil)
        runtime.completeMockPomodoro()
        await runtime.syncFromAdapter()
        try expect(runtime.feed())
        try expect(runtime.eatStartedAt != nil)
        await runtime.waitForEatToFinish()
        try expect(runtime.eatStartedAt == nil)
    }

    static func quietAdapterSyncDoesNotKeepNotifying() async throws {
        let (runtime, _, _) = makeRuntime()
        let counter = NotifyCounter()
        runtime.onChange = { counter.increment() }
        await runtime.syncFromAdapter()
        let afterFirst = counter.value
        await runtime.syncFromAdapter()
        await runtime.syncFromAdapter()
        try expectEqual(counter.value, afterFirst)
        try expect(afterFirst <= 1)
    }
}

private final class NotifyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}

enum PetMotionSuite {
    static func breathLoopsAndExpandsOnInhale() async throws {
        let period = PetMotion.breathPeriod
        let rest = PetMotion.breathScaleY(elapsed: 0)
        let inhale = PetMotion.breathScaleY(elapsed: period / 4)
        let mid = PetMotion.breathScaleY(elapsed: period / 2)
        let exhale = PetMotion.breathScaleY(elapsed: 3 * period / 4)
        let looped = PetMotion.breathScaleY(elapsed: period)

        try expectClose(Double(rest), 1)
        try expect(inhale > rest)
        try expectClose(Double(mid), 1)
        try expect(exhale < rest)
        try expectClose(Double(looped), Double(rest))
        try expect(PetMotion.breathScaleY(elapsed: period / 4) > PetMotion.breathScaleX(elapsed: period / 4))
    }

    static func studyTiltLooksDownAndNods() async throws {
        let period = PetMotion.studyPeriod
        let start = PetMotion.studyTiltDegrees(elapsed: 0)
        let nod = PetMotion.studyTiltDegrees(elapsed: period / 4)
        try expect(start < 0)
        try expect(nod < start)
        try expectClose(PetMotion.studyPageFlip(elapsed: 0), 0)
        try expectClose(PetMotion.studyPageFlip(elapsed: PetMotion.studyPagePeriod / 2), 1, tolerance: 0.02)
    }

    static func eatTomatoApproachesThenDisappears() async throws {
        try expectClose(Double(PetMotion.eatProgress(elapsed: -1, duration: 2)), 0)
        try expectClose(Double(PetMotion.eatProgress(elapsed: 1, duration: 2)), 0.5)
        try expectClose(Double(PetMotion.eatProgress(elapsed: 3, duration: 2)), 1)

        let start = PetMotion.eatPose(progress: 0)
        let approaching = PetMotion.eatPose(progress: 0.2)
        let chewing = PetMotion.eatPose(progress: 0.5)
        let done = PetMotion.eatPose(progress: 1)

        try expectClose(Double(start.tomatoOpacity), 1)
        try expectClose(Double(start.tomatoTravel), 0)
        try expect(approaching.tomatoTravel > start.tomatoTravel)
        try expect(abs(start.tomatoRotation) > abs(approaching.tomatoRotation))
        try expect(chewing.characterScaleY != 1)
        try expect(chewing.tomatoScale < start.tomatoScale)
        try expectClose(Double(done.tomatoOpacity), 0)
        try expectClose(Double(done.characterScaleY), 1)
        try expectClose(done.tomatoRotation, 0)
    }

    static func tomatoTravelsFromLapToMouth() async throws {
        let size: CGFloat = 220
        let start = PetMotion.tomatoOffset(travel: 0, size: size)
        let mid = PetMotion.tomatoOffset(travel: 0.5, size: size)
        let end = PetMotion.tomatoOffset(travel: 1, size: size)

        try expect(start.x > end.x)
        try expect(start.y > end.y)
        try expect(mid.x < start.x && mid.x > end.x)
        try expectClose(Double(PetMotion.tomatoDropPoints), 72 / 2.54, tolerance: 0.01)
        try expectClose(Double(start.y), Double(size * 0.26 + PetMotion.tomatoDropPoints), tolerance: 0.01)
        try expectClose(Double(end.y), Double(size * 0.05 + PetMotion.tomatoDropPoints), tolerance: 0.01)
        try expect(end.x > -size * 0.04)
        try expect(end.x < size * 0.08)
    }

    static func looksTowardMouseLikeInventory() async throws {
        let center = CGPoint(x: 200, y: 200)
        let size: CGFloat = 220
        let still = PetMotion.lookPose(mouse: center, petCenter: center, petSize: size)
        let right = PetMotion.lookPose(mouse: CGPoint(x: 400, y: 200), petCenter: center, petSize: size)
        let left = PetMotion.lookPose(mouse: CGPoint(x: 0, y: 200), petCenter: center, petSize: size)
        let up = PetMotion.lookPose(mouse: CGPoint(x: 200, y: 400), petCenter: center, petSize: size)
        let far = PetMotion.lookPose(mouse: CGPoint(x: 4000, y: 200), petCenter: center, petSize: size)
        let farther = PetMotion.lookPose(mouse: CGPoint(x: 8000, y: 200), petCenter: center, petSize: size)

        try expectClose(Double(still.eyeX), 0, tolerance: 0.05)
        try expectClose(Double(still.eyeY), 0, tolerance: 0.05)
        try expect(right.eyeX > 0)
        try expect(left.eyeX < 0)
        try expect(right.headTilt > 0)
        try expect(left.headTilt < 0)
        try expect(right.offsetX > 0)
        try expect(left.offsetX < 0)
        try expect(up.eyeY > 0)
        try expect(up.offsetY < 0)
        try expect(abs(right.headTilt) > 6)
        try expectClose(Double(far.eyeX), Double(farther.eyeX), tolerance: 0.05)
        try expect(PetMotion.lookWeight(state: .rest, isResizing: false) > PetMotion.lookWeight(state: .study, isResizing: false))
        try expect(PetMotion.lookWeight(state: .eat, isResizing: false) < PetMotion.lookWeight(state: .rest, isResizing: false))

        let blended = PetMotion.blendLook(LookPose.zero, toward: right, factor: 0.5)
        try expect(abs(Double(blended.eyeX)) > 0)
        try expect(abs(Double(blended.eyeX)) < abs(Double(right.eyeX)))
    }

    static func glintStaysAlignedWhenResized() async throws {
        let image = CGSize(width: 1280, height: 1229)
        let unit = PetMotion.leftEyeCenter
        let atDefault = PetMotion.glintCenter(unit: unit, imageSize: image, viewSize: PetSizing.defaultSize)
        let doubled = PetMotion.glintCenter(unit: unit, imageSize: image, viewSize: PetSizing.defaultSize * 2)
        let halved = PetMotion.glintCenter(unit: unit, imageSize: image, viewSize: PetSizing.defaultSize / 2)

        try expectClose(Double(doubled.x / atDefault.x), 2, tolerance: 0.02)
        try expectClose(Double(doubled.y / atDefault.y), 2, tolerance: 0.02)
        try expectClose(Double(halved.x / atDefault.x), 0.5, tolerance: 0.02)
        try expectClose(Double(halved.y / atDefault.y), 0.5, tolerance: 0.02)

        let fitted = PetMotion.aspectFit(imageSize: image, in: CGSize(width: PetSizing.defaultSize, height: PetSizing.defaultSize))
        let drop = atDefault.y - (fitted.minY + unit.y * fitted.height)
        try expectClose(Double(drop), Double(PetMotion.glintDropPoints), tolerance: 0.05)
    }

    static func glintUnitRoundTripsAndClamps() async throws {
        let image = CGSize(width: 1280, height: 1229)
        let view: CGFloat = 220
        let unit = CGPoint(x: 0.41, y: 0.53)
        let point = PetMotion.glintCenter(unit: unit, imageSize: image, viewSize: view)
        let back = PetMotion.unitPoint(fromView: point, imageSize: image, viewSize: view)
        try expectClose(Double(back.x), Double(unit.x), tolerance: 0.004)
        try expectClose(Double(back.y), Double(unit.y), tolerance: 0.004)

        let clamped = PetMotion.clampGlintUnit(CGPoint(x: -1, y: 2))
        try expect(clamped.x > 0)
        try expect(clamped.x < 1)
        try expect(clamped.y > 0)
        try expect(clamped.y < 1)
        try expect(clamped.x != -1)
    }
}

enum PetEnergySuite {
    static func drivesFramesOnlyWhenSomeoneCanSeeThem() async throws {
        try expect(
            PetEnergy.shouldDriveFrames(
                isWindowOnscreen: true,
                isWindowOccluded: false,
                isDisplayAsleep: false,
                isScreenLocked: false,
                isPoseFrozen: false
            )
        )
        try expect(
            !PetEnergy.shouldDriveFrames(
                isWindowOnscreen: false,
                isWindowOccluded: false,
                isDisplayAsleep: false,
                isScreenLocked: false,
                isPoseFrozen: false
            )
        )
        try expect(
            !PetEnergy.shouldDriveFrames(
                isWindowOnscreen: true,
                isWindowOccluded: true,
                isDisplayAsleep: false,
                isScreenLocked: false,
                isPoseFrozen: false
            )
        )
        try expect(
            !PetEnergy.shouldDriveFrames(
                isWindowOnscreen: true,
                isWindowOccluded: false,
                isDisplayAsleep: true,
                isScreenLocked: false,
                isPoseFrozen: false
            )
        )
        try expect(
            !PetEnergy.shouldDriveFrames(
                isWindowOnscreen: true,
                isWindowOccluded: false,
                isDisplayAsleep: false,
                isScreenLocked: true,
                isPoseFrozen: false
            )
        )
        try expect(
            !PetEnergy.shouldDriveFrames(
                isWindowOnscreen: true,
                isWindowOccluded: false,
                isDisplayAsleep: false,
                isScreenLocked: false,
                isPoseFrozen: true
            )
        )
        try expectClose(PetEnergy.motionFrameInterval, 1.0 / 30.0)
    }

    static func skipsLookBlendOnceEyesHaveSettled() async throws {
        let target = PetMotion.lookPose(
            mouse: CGPoint(x: 400, y: 200),
            petCenter: CGPoint(x: 200, y: 200),
            petSize: 220
        )
        try expect(!PetEnergy.lookHasSettled(.zero, target))
        try expect(PetEnergy.lookHasSettled(target, target))
        let almost = LookPose(
            eyeX: target.eyeX + 0.0001,
            eyeY: target.eyeY,
            headTilt: target.headTilt,
            offsetX: target.offsetX,
            offsetY: target.offsetY
        )
        try expect(PetEnergy.lookHasSettled(almost, target))
        try expect(!PetEnergy.mouseMoved(CGPoint(x: 10, y: 10), CGPoint(x: 10.2, y: 10.1)))
        try expect(PetEnergy.mouseMoved(CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 10)))
    }
}
