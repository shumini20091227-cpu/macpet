import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: Bool, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if !condition {
        throw TestFailure(description: "\(file):\(line) \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: String = #fileID, line: Int = #line) throws {
    if actual != expected {
        throw TestFailure(description: "\(file):\(line) expected \(expected), got \(actual)")
    }
}

func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.001, file: String = #fileID, line: Int = #line) throws {
    if abs(actual - expected) > tolerance {
        throw TestFailure(description: "\(file):\(line) expected \(expected) ±\(tolerance), got \(actual)")
    }
}

@main
enum MacPetCoreTestRunner {
    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("twentyFiveMinutesGrantsOneFood", FoodEngineSuite.twentyFiveMinutesGrantsOneFood),
            ("fortyNineMinutesGrantsOneFood", FoodEngineSuite.fortyNineMinutesGrantsOneFood),
            ("fiftyMinutesGrantsTwoFoods", FoodEngineSuite.fiftyMinutesGrantsTwoFoods),
            ("sessionShorterThanMinimumGrantsNothing", FoodEngineSuite.sessionShorterThanMinimumGrantsNothing),
            ("duplicateSessionIsNotRewardedTwice", FoodEngineSuite.duplicateSessionIsNotRewardedTwice),
            ("dailyCapBlocksAdditionalFood", FoodEngineSuite.dailyCapBlocksAdditionalFood),
            ("newDayResetsDailyCapButKeepsFood", FoodEngineSuite.newDayResetsDailyCapButKeepsFood),
            ("feedDeductsOneFood", FoodEngineSuite.feedDeductsOneFood),
            ("feedFailsWhenEmpty", FoodEngineSuite.feedFailsWhenEmpty),
            ("startsInRest", PetStateMachineSuite.startsInRest),
            ("liveSessionMovesToStudy", PetStateMachineSuite.liveSessionMovesToStudy),
            ("endingLiveSessionReturnsToRest", PetStateMachineSuite.endingLiveSessionReturnsToRest),
            ("startEatingMovesToEatFromRestOrStudy", PetStateMachineSuite.startEatingMovesToEatFromRestOrStudy),
            ("liveSessionDoesNotLeaveEatUntilFinished", PetStateMachineSuite.liveSessionDoesNotLeaveEatUntilFinished),
            ("finishEatingReturnsToRest", PetStateMachineSuite.finishEatingReturnsToRest),
            ("zeroMovementIsClick", PetGestureSuite.zeroMovementIsClick),
            ("movementAtOrBelowThresholdIsClick", PetGestureSuite.movementAtOrBelowThresholdIsClick),
            ("movementBeyondThresholdIsDrag", PetGestureSuite.movementBeyondThresholdIsDrag),
            ("completePomodoroCreatesTwentyFiveMinuteSession", MockAdapterSuite.completePomodoroCreatesTwentyFiveMinuteSession),
            ("startAndStopFocusTracksLiveSession", MockAdapterSuite.startAndStopFocusTracksLiveSession),
            ("persistsFoodLedgerAndWindow", AppStoreSuite.persistsFoodLedgerAndWindow),
            ("defaultLedgerIsEmpty", AppStoreSuite.defaultLedgerIsEmpty),
            ("opensWebChatGPT", ChatGPTSuite.opensWebChatGPT),
            ("completingMockPomodoroAddsFood", PetRuntimeSuite.completingMockPomodoroAddsFood),
            ("feedingConsumesFoodAndPlaysEatThenRest", PetRuntimeSuite.feedingConsumesFoodAndPlaysEatThenRest),
            ("feedFailsWithoutFood", PetRuntimeSuite.feedFailsWithoutFood),
            ("liveFocusMovesPetToStudy", PetRuntimeSuite.liveFocusMovesPetToStudy),
            ("leftClickOpensChatGPT", PetRuntimeSuite.leftClickOpensChatGPT),
            ("breathLoopsAndExpandsOnInhale", PetMotionSuite.breathLoopsAndExpandsOnInhale),
            ("studyTiltLooksDownAndNods", PetMotionSuite.studyTiltLooksDownAndNods),
            ("eatTomatoApproachesThenDisappears", PetMotionSuite.eatTomatoApproachesThenDisappears),
            ("feedRecordsEatStartTime", PetRuntimeSuite.feedRecordsEatStartTime),
            ("tomatoTravelsFromLapToMouth", PetMotionSuite.tomatoTravelsFromLapToMouth),
            ("clampsSizeToAllowedRange", PetSizingSuite.clampsSizeToAllowedRange),
            ("cornerDragGrowsAndShrinks", PetSizingSuite.cornerDragGrowsAndShrinks),
            ("windowGrowsWhenResizing", PetSizingSuite.windowGrowsWhenResizing),
            ("looksTowardMouseLikeInventory", PetMotionSuite.looksTowardMouseLikeInventory),
            ("glintStaysAlignedWhenResized", PetMotionSuite.glintStaysAlignedWhenResized),
            ("glintUnitRoundTripsAndClamps", PetMotionSuite.glintUnitRoundTripsAndClamps),
            ("drivesFramesOnlyWhenSomeoneCanSeeThem", PetEnergySuite.drivesFramesOnlyWhenSomeoneCanSeeThem),
            ("skipsLookBlendOnceEyesHaveSettled", PetEnergySuite.skipsLookBlendOnceEyesHaveSettled),
            ("quietAdapterSyncDoesNotKeepNotifying", PetRuntimeSuite.quietAdapterSyncDoesNotKeepNotifying)
        ]

        var failed = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS \(name)")
            } catch {
                failed += 1
                print("FAIL \(name): \(error)")
            }
        }

        print("\(tests.count - failed)/\(tests.count) passed")
        if failed > 0 {
            exit(1)
        }
    }
}
