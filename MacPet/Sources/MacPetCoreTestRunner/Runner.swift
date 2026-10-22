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
            ("schedulesOnlyAtFrameChangesAndCapsRefreshRate", PetAnimationSuite.schedulesOnlyAtFrameChangesAndCapsRefreshRate),
            ("powerModeSetsFrameBudget", PetEnergySuite.powerModeSetsFrameBudget),
            ("animatedGIFKeepsTimingTransparencyAndLoops", PetAnimationSuite.animatedGIFKeepsTimingTransparencyAndLoops),
            ("invalidAnimationIsRejected", PetAnimationSuite.invalidAnimationIsRejected),
            ("zeroMovementIsClick", PetGestureSuite.zeroMovementIsClick),
            ("movementAtOrBelowThresholdIsClick", PetGestureSuite.movementAtOrBelowThresholdIsClick),
            ("movementBeyondThresholdIsDrag", PetGestureSuite.movementBeyondThresholdIsDrag),
            ("persistsWindowSettings", AppStoreSuite.persistsWindowSettings),
            ("defaultWindowSettings", AppStoreSuite.defaultWindowSettings),
            ("opensWebChatGPT", ChatGPTSuite.opensWebChatGPT),
            ("breathLoopsAndExpandsOnInhale", PetMotionSuite.breathLoopsAndExpandsOnInhale),
            ("clampsSizeToAllowedRange", PetSizingSuite.clampsSizeToAllowedRange),
            ("cornerDragGrowsAndShrinks", PetSizingSuite.cornerDragGrowsAndShrinks),
            ("windowGrowsWhenResizing", PetSizingSuite.windowGrowsWhenResizing),
            ("looksTowardMouseLikeInventory", PetMotionSuite.looksTowardMouseLikeInventory),
            ("glintStaysAlignedWhenResized", PetMotionSuite.glintStaysAlignedWhenResized),
            ("glintUnitRoundTripsAndClamps", PetMotionSuite.glintUnitRoundTripsAndClamps),
            ("drivesFramesOnlyWhenSomeoneCanSeeThem", PetEnergySuite.drivesFramesOnlyWhenSomeoneCanSeeThem),
            ("skipsLookBlendOnceEyesHaveSettled", PetEnergySuite.skipsLookBlendOnceEyesHaveSettled),
            ("usesCustomImageWhenPresentOtherwiseBundled", PetCharacterStoreSuite.usesCustomImageWhenPresentOtherwiseBundled)
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

