import CoreGraphics
import Foundation

public enum PetEnergy {
    public static let motionFrameInterval: TimeInterval = 1.0 / 30.0
    public static let motionTimerTolerance: TimeInterval = 1.0 / 60.0
    public static let lookSettledEpsilon: CGFloat = 0.0005
    public static let mouseStillThreshold: CGFloat = 0.5

    public static func shouldDriveFrames(
        isWindowOnscreen: Bool,
        isWindowOccluded: Bool,
        isDisplayAsleep: Bool,
        isScreenLocked: Bool,
        isPoseFrozen: Bool
    ) -> Bool {
        isWindowOnscreen && !isWindowOccluded && !isDisplayAsleep && !isScreenLocked && !isPoseFrozen
    }

    public static func lookHasSettled(
        _ current: LookPose,
        _ target: LookPose,
        epsilon: CGFloat = lookSettledEpsilon
    ) -> Bool {
        abs(current.eyeX - target.eyeX) < epsilon
            && abs(current.eyeY - target.eyeY) < epsilon
            && abs(current.headTilt - target.headTilt) < Double(epsilon * 20)
            && abs(current.offsetX - target.offsetX) < epsilon * 8
            && abs(current.offsetY - target.offsetY) < epsilon * 8
    }

    public static func mouseMoved(
        _ previous: CGPoint,
        _ current: CGPoint,
        threshold: CGFloat = mouseStillThreshold
    ) -> Bool {
        hypot(previous.x - current.x, previous.y - current.y) >= threshold
    }
}
