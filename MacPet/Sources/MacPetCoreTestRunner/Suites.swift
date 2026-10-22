import CoreGraphics
import Foundation
import MacPetCore

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

enum AppStoreSuite {
    private static func makeStore() -> AppStore {
        let suite = "MacPetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppStore(defaults: defaults)
    }

    static func persistsWindowSettings() async throws {
        let store = makeStore()
        store.windowOrigin = CGPoint(x: 120, y: 80)
        store.isWindowHidden = true
        try expectEqual(store.windowOrigin, CGPoint(x: 120, y: 80))
        try expect(store.isWindowHidden)
        store.petSize = 300
        try expectClose(Double(store.petSize), 300)
        store.leftGlint = CGPoint(x: 0.40, y: 0.55)
        store.rightGlint = CGPoint(x: 0.62, y: 0.54)
        try expectClose(Double(store.leftGlint.x), 0.40)
        try expectClose(Double(store.rightGlint.x), 0.62)
    }

    static func defaultWindowSettings() async throws {
        let store = makeStore()
        try expect(store.windowOrigin == nil)
        try expect(!store.isWindowHidden)
        try expectClose(Double(store.petSize), Double(PetSizing.defaultSize))
        try expectClose(Double(store.leftGlint.x), Double(PetMotion.leftEyeCenter.x))
        try expectClose(Double(store.rightGlint.x), Double(PetMotion.rightEyeCenter.x))
    }
}

enum PetCharacterStoreSuite {
    private static func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacPetCharacter.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writePNG(named name: String, in directory: URL, marker: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(marker.utf8).write(to: url)
        return url
    }

    static func usesCustomImageWhenPresentOtherwiseBundled() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundled = try writePNG(named: "bundled.png", in: directory, marker: "bundled")
        try expectEqual(
            PetCharacterStore.resolvedImageURL(directory: directory, bundled: [bundled])?.lastPathComponent,
            "bundled.png"
        )

        let first = try writePNG(named: "first.png", in: directory, marker: "first")
        try PetCharacterStore.install(from: first, into: directory)
        try expect(PetCharacterStore.hasCustomImage(in: directory))
        let custom = PetCharacterStore.resolvedImageURL(directory: directory, bundled: [bundled])
        try expectEqual(custom?.lastPathComponent, PetCharacterStore.fileName)
        try expectEqual(String(data: try Data(contentsOf: custom!), encoding: .utf8), "first")

        let second = try writePNG(named: "second.png", in: directory, marker: "second")
        try PetCharacterStore.install(from: second, into: directory)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        try expectEqual(files.filter { $0 == PetCharacterStore.fileName }.count, 1)
        try expectEqual(String(data: try Data(contentsOf: PetCharacterStore.customImageURL(in: directory)), encoding: .utf8), "second")

        try PetCharacterStore.removeCustom(in: directory)
        try expect(!PetCharacterStore.hasCustomImage(in: directory))
        try expectEqual(
            PetCharacterStore.resolvedImageURL(directory: directory, bundled: [bundled])?.lastPathComponent,
            "bundled.png"
        )
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

        try expectEqual(PetMotion.lookWeight(isResizing: false), 1)
        try expectEqual(PetMotion.lookWeight(isResizing: true), 0.25)

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

        let fromFitted = PetMotion.glintCenter(unit: unit, in: fitted, viewSize: PetSizing.defaultSize)
        try expectClose(Double(fromFitted.x), Double(atDefault.x))
        try expectClose(Double(fromFitted.y), Double(atDefault.y))

        let boxed = CGRect(x: 10, y: 20, width: 200, height: 200)
        let fittedInBox = PetMotion.aspectFit(imageSize: image, in: boxed)
        try expectClose(Double(fittedInBox.minX), Double(boxed.minX + PetMotion.aspectFit(imageSize: image, in: boxed.size).minX))
        try expectClose(Double(fittedInBox.minY), Double(boxed.minY + PetMotion.aspectFit(imageSize: image, in: boxed.size).minY))
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
    static func powerModeSetsFrameBudget() async throws {
        try expectEqual(PetEnergy.maximumFPS(energySaving: false, lowPower: false), 30)
        try expectEqual(PetEnergy.maximumFPS(energySaving: true, lowPower: false), 12)
        try expectEqual(PetEnergy.maximumFPS(energySaving: false, lowPower: true), 6)
        try expectEqual(PetEnergy.maximumFPS(energySaving: true, lowPower: true), 6)
    }

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



enum PetAnimationSuite {
    static func schedulesOnlyAtFrameChangesAndCapsRefreshRate() async throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("MacPet/Resources")
        let animation = try PetAnimation(url: resources.appendingPathComponent("思考中.gif"))
        try expectClose(animation.nextFrameDelay(elapsed: 0, speed: 0.25, maximumFPS: 12)!, 0.161)
        try expectClose(animation.nextFrameDelay(elapsed: 0, speed: 1, maximumFPS: 12)!, 1.0 / 12)
        try expectClose(animation.nextFrameDelay(elapsed: 0, speed: 1, maximumFPS: 6)!, 1.0 / 6)
        try expectClose(animation.nextFrameDelay(elapsed: animation.duration + 0.01,
            speed: 0.25, maximumFPS: 30)!, 0.121)
        let still = try PetAnimation(url: resources.appendingPathComponent("pet_character.png"))
        try expect(still.nextFrameDelay(elapsed: 0, speed: 1, maximumFPS: 12) == nil)
    }

    static func animatedGIFKeepsTimingTransparencyAndLoops() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("MacPet/Resources/思考中.gif")
        let animation = try PetAnimation(url: url)
        try expectEqual(animation.frames.count, 24)
        try expectClose(animation.duration, 0.96)
        try expectEqual(animation.frameIndex(elapsed: 0), 0)
        try expectEqual(animation.frameIndex(elapsed: 0.041), 1)
        try expectEqual(animation.frameIndex(elapsed: 0.95), 23)
        try expectEqual(animation.frameIndex(elapsed: animation.duration + 0.041), 1)
        let frame = animation.frames[0]
        try expectEqual(frame.width, 500)
        try expectEqual(frame.bitsPerPixel, 32)
        let data = frame.dataProvider!.data!
        let pixels = CFDataGetBytePtr(data)!
        try expectEqual(pixels[3], 0)
        try expectEqual(animation.frameIndex(elapsed: -1), 0)
    }

    static func invalidAnimationIsRejected() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        try Data("invalid gif".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try PetAnimation(url: file)
        } catch { return }
        throw TestFailure(description: "Invalid animation was accepted")
    }
}
