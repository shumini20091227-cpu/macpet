import CoreGraphics
import Foundation

public enum GlintSlot: String, CaseIterable, Sendable {
    case left
    case right
}

public struct EatPose: Equatable, Sendable {
    public var characterScaleY: CGFloat
    public var characterOffsetY: CGFloat
    public var tomatoTravel: CGFloat
    public var tomatoScale: CGFloat
    public var tomatoOpacity: CGFloat
    public var tomatoRotation: Double

    public init(
        characterScaleY: CGFloat,
        characterOffsetY: CGFloat,
        tomatoTravel: CGFloat,
        tomatoScale: CGFloat,
        tomatoOpacity: CGFloat,
        tomatoRotation: Double
    ) {
        self.characterScaleY = characterScaleY
        self.characterOffsetY = characterOffsetY
        self.tomatoTravel = tomatoTravel
        self.tomatoScale = tomatoScale
        self.tomatoOpacity = tomatoOpacity
        self.tomatoRotation = tomatoRotation
    }
}

public struct LookPose: Equatable, Sendable {
    public var eyeX: CGFloat
    public var eyeY: CGFloat
    public var headTilt: Double
    public var offsetX: CGFloat
    public var offsetY: CGFloat

    public static let zero = LookPose(eyeX: 0, eyeY: 0, headTilt: 0, offsetX: 0, offsetY: 0)

    public init(eyeX: CGFloat, eyeY: CGFloat, headTilt: Double, offsetX: CGFloat, offsetY: CGFloat) {
        self.eyeX = eyeX
        self.eyeY = eyeY
        self.headTilt = headTilt
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public func scaled(by weight: CGFloat) -> LookPose {
        LookPose(
            eyeX: eyeX * weight,
            eyeY: eyeY * weight,
            headTilt: headTilt * Double(weight),
            offsetX: offsetX * weight,
            offsetY: offsetY * weight
        )
    }
}

public enum PetMotion {
    public static let breathPeriod: TimeInterval = 2.6
    public static let studyPeriod: TimeInterval = 2.0
    public static let studyPagePeriod: TimeInterval = 1.6
    /// 1 cm at 72 points per inch.
    public static let tomatoDropPoints: CGFloat = 72 / 2.54
    /// Extra glint shift along +y (down). Zero keeps highlights on the eyes.
    public static let glintDropPoints: CGFloat = 0
    public static let lookHeadTiltAmplitude: Double = 14
    public static let lookOffsetXAmplitude: CGFloat = 16
    public static let lookOffsetYAmplitude: CGFloat = 12
    public static let lookBlend: CGFloat = 0.32
    public static let leftEyeCenter = CGPoint(x: 0.372, y: 0.542)
    public static let rightEyeCenter = CGPoint(x: 0.615, y: 0.536)
    public static let eyeWidthFraction: CGFloat = 0.108
    public static let eyeHeightFraction: CGFloat = 0.050
    public static let neckAnchor = CGPoint(x: 0.50, y: 0.60)
    public static let lookBodyAnchor = CGPoint(x: 0.50, y: 0.84)

    public static func breathScaleY(elapsed: TimeInterval) -> CGFloat {
        1 + 0.045 * sine(elapsed: elapsed, period: breathPeriod)
    }

    public static func breathScaleX(elapsed: TimeInterval) -> CGFloat {
        1 + 0.012 * sine(elapsed: elapsed, period: breathPeriod)
    }

    public static func breathLift(elapsed: TimeInterval) -> CGFloat {
        2.4 * sine(elapsed: elapsed, period: breathPeriod)
    }

    public static func studyTiltDegrees(elapsed: TimeInterval) -> Double {
        -4.5 - 3.5 * Double(sine(elapsed: elapsed, period: studyPeriod))
    }

    public static func studyPageFlip(elapsed: TimeInterval) -> Double {
        abs(sin(.pi * elapsed / studyPagePeriod))
    }

    public static func lookPose(mouse: CGPoint, petCenter: CGPoint, petSize: CGFloat) -> LookPose {
        let range = max(petSize * 1.8, 1)
        let dx = max(-1, min(1, (mouse.x - petCenter.x) / range))
        let dy = max(-1, min(1, (mouse.y - petCenter.y) / range))
        let x = CGFloat(tanh(Double(dx) * 1.25))
        let y = CGFloat(tanh(Double(dy) * 1.25))
        return LookPose(
            eyeX: x,
            eyeY: y,
            headTilt: Double(x) * lookHeadTiltAmplitude,
            offsetX: x * lookOffsetXAmplitude,
            offsetY: -y * lookOffsetYAmplitude
        )
    }

    public static func lookWeight(state: PetState, isResizing: Bool) -> CGFloat {
        let base: CGFloat
        switch state {
        case .rest: base = 1
        case .study: base = 0.4
        case .eat: base = 0.3
        }
        return isResizing ? base * 0.25 : base
    }

    public static func aspectFit(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        let scale = min(bounds.width / max(imageSize.width, 1), bounds.height / max(imageSize.height, 1))
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }

    public static func aspectFit(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        aspectFit(imageSize: imageSize, in: bounds.size).offsetBy(dx: bounds.minX, dy: bounds.minY)
    }

    public static func glintDrop(forViewSize viewSize: CGFloat) -> CGFloat {
        glintDropPoints * (viewSize / PetSizing.defaultSize)
    }

    public static func glintCenter(unit: CGPoint, in fitted: CGRect, viewSize: CGFloat) -> CGPoint {
        CGPoint(
            x: fitted.minX + unit.x * fitted.width,
            y: fitted.minY + unit.y * fitted.height + glintDrop(forViewSize: viewSize)
        )
    }

    public static func glintCenter(unit: CGPoint, imageSize: CGSize, viewSize: CGFloat) -> CGPoint {
        glintCenter(
            unit: unit,
            in: aspectFit(imageSize: imageSize, in: CGSize(width: viewSize, height: viewSize)),
            viewSize: viewSize
        )
    }

    public static func unitPoint(fromView point: CGPoint, imageSize: CGSize, viewSize: CGFloat) -> CGPoint {
        let fitted = aspectFit(imageSize: imageSize, in: CGSize(width: viewSize, height: viewSize))
        let drop = glintDrop(forViewSize: viewSize)
        let x = fitted.width > 0 ? (point.x - fitted.minX) / fitted.width : 0.5
        let y = fitted.height > 0 ? (point.y - fitted.minY - drop) / fitted.height : 0.5
        return clampGlintUnit(CGPoint(x: x, y: y))
    }

    public static func clampGlintUnit(_ unit: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(unit.x, 0.18), 0.82),
            y: min(max(unit.y, 0.32), 0.72)
        )
    }

    public static let glintHandleSize: CGFloat = 28

    public static func blendLook(_ current: LookPose, toward target: LookPose, factor: CGFloat) -> LookPose {
        let t = max(0, min(1, factor))
        return LookPose(
            eyeX: current.eyeX + (target.eyeX - current.eyeX) * t,
            eyeY: current.eyeY + (target.eyeY - current.eyeY) * t,
            headTilt: current.headTilt + (target.headTilt - current.headTilt) * Double(t),
            offsetX: current.offsetX + (target.offsetX - current.offsetX) * t,
            offsetY: current.offsetY + (target.offsetY - current.offsetY) * t
        )
    }

    public static func eatProgress(elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 1 }
        return CGFloat(min(max(elapsed / duration, 0), 1))
    }

    public static func tomatoOffset(travel: CGFloat, size: CGFloat) -> CGPoint {
        let t = min(max(travel, 0), 1)
        let start = CGPoint(x: size * 0.20, y: size * 0.26 + tomatoDropPoints)
        let end = CGPoint(x: size * 0.02, y: size * 0.05 + tomatoDropPoints)
        return CGPoint(
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t
        )
    }

    public static func eatPose(progress: CGFloat) -> EatPose {
        let progress = min(max(progress, 0), 1)
        let approachEnd: CGFloat = 0.32
        let chewEnd: CGFloat = 0.84

        if progress < approachEnd {
            let t = progress / approachEnd
            let eased = t * t * (3 - 2 * t)
            return EatPose(
                characterScaleY: 1 + 0.02 * eased,
                characterOffsetY: 2 * eased,
                tomatoTravel: eased,
                tomatoScale: 1,
                tomatoOpacity: 1,
                tomatoRotation: 16 * Double(1 - eased)
            )
        }

        if progress < chewEnd {
            let chewT = (progress - approachEnd) / (chewEnd - approachEnd)
            let bite = abs(sin(chewT * 5 * .pi))
            return EatPose(
                characterScaleY: 1 + 0.08 * bite,
                characterOffsetY: 4 * bite,
                tomatoTravel: 1,
                tomatoScale: 1 - 0.72 * chewT,
                tomatoOpacity: 1 - 0.12 * chewT,
                tomatoRotation: 6 * Double(sin(chewT * 6 * .pi))
            )
        }

        let fade = (progress - chewEnd) / (1 - chewEnd)
        return EatPose(
            characterScaleY: 1,
            characterOffsetY: 0,
            tomatoTravel: 1,
            tomatoScale: 0.16,
            tomatoOpacity: max(0, 1 - fade),
            tomatoRotation: 0
        )
    }

    private static func sine(elapsed: TimeInterval, period: TimeInterval) -> CGFloat {
        CGFloat(sin(2 * Double.pi * elapsed / period))
    }
}
