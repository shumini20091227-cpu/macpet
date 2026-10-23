import AppKit
import MacPetCore
import Observation
import SwiftUI

@MainActor
@Observable
final class PetDisplay {
    var expressionImage: NSImage?
    var expressionFrame: Int = 0
    var tick: Date = Date()
    var look: LookPose = .zero
    var banner: String?
}

struct PetView: View {
    @Bindable var display: PetDisplay
    var size: CGFloat
    var reduceMotion: Bool
    var isResizing: Bool = false
    var isEditingGlints: Bool = false
    var leftGlint: CGPoint = PetMotion.leftEyeCenter
    var rightGlint: CGPoint = PetMotion.rightEyeCenter

    var body: some View {
        let windowLength = PetSizing.windowLength(petSize: size, isResizing: isResizing)
        ZStack {
            canvas(at: display.tick)
                .frame(width: size, height: size)
            if isResizing {
                ResizeChrome(petSize: size, windowLength: windowLength)
            }
        }
        .frame(width: windowLength, height: windowLength)
        .background(Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("桌面宠物")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            isEditingGlints
                ? "拖动眼睛高光，右键完成调整"
                : isResizing ? "拖动边角调整大小，右键完成调整" : "单击打开 ChatGPT，右键管理表情、调整速度或退出"
        )
    }

    private func canvas(at date: Date) -> some View {
        let elapsed = date.timeIntervalSinceReferenceDate
        let pose = currentPose(elapsed: elapsed, now: date)

        return ZStack {
            ZStack {
                character()
                    .frame(width: size, height: size)
                    .overlay {
                        if !PetExpressions.isActive {
                            GazeOverlay(
                                size: size,
                                look: isEditingGlints ? .zero : display.look,
                                leftGlint: leftGlint,
                                rightGlint: rightGlint,
                                isEditing: isEditingGlints
                            )
                        }
                    }
            }
            .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
            .rotationEffect(
                .degrees(pose.tilt),
                anchor: UnitPoint(x: PetMotion.neckAnchor.x, y: PetMotion.neckAnchor.y)
            )
            .rotationEffect(
                .degrees(pose.lookTilt),
                anchor: UnitPoint(x: PetMotion.lookBodyAnchor.x, y: PetMotion.lookBodyAnchor.y)
            )
            .offset(x: pose.offsetX, y: pose.offsetY)

            if let banner = display.banner {
                Text(banner)
                    .font(.system(size: max(10, size * 0.055), weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .offset(y: -size * 0.42)
                    .accessibilityHidden(true)
            }
        }
    }

    private func currentPose(elapsed: TimeInterval, now: Date) -> VisualPose {
        if isEditingGlints || PetExpressions.isActive {
            return VisualPose(scaleX: 1, scaleY: 1, tilt: 0, lookTilt: 0, offsetX: 0, offsetY: 0)
        }
        let damp: CGFloat = reduceMotion ? 0.55 : 1
        return VisualPose(
            scaleX: 1 + (PetMotion.breathScaleX(elapsed: elapsed) - 1) * damp,
            scaleY: 1 + (PetMotion.breathScaleY(elapsed: elapsed) - 1) * damp,
            tilt: Double(1.1 * damp) * sin(elapsed * 1.15),
            lookTilt: display.look.headTilt * Double(damp),
            offsetX: display.look.offsetX * damp,
            offsetY: -PetMotion.breathLift(elapsed: elapsed) * damp + display.look.offsetY * damp
        )
    }

    private var accessibilityValue: String {
        isEditingGlints ? "调整高光" : isResizing ? "调整大小" : "桌面陪伴"
    }

    @ViewBuilder
    private func character() -> some View {
        if let image = display.expressionImage ?? PetAsset.characterImage() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Circle()
                .fill(Color(red: 13 / 255, green: 148 / 255, blue: 136 / 255))
                .overlay {
                    Circle()
                        .stroke(Color(red: 19 / 255, green: 78 / 255, blue: 74 / 255), lineWidth: 3)
                }
                .padding(size * 0.12)
        }
    }
}

private struct VisualPose {
    var scaleX: CGFloat
    var scaleY: CGFloat
    var tilt: Double
    var lookTilt: Double
    var offsetX: CGFloat
    var offsetY: CGFloat
}

private struct GazeOverlay: View {
    var size: CGFloat
    var look: LookPose
    var leftGlint: CGPoint
    var rightGlint: CGPoint
    var isEditing: Bool

    var body: some View {
        let fitted = PetMotion.aspectFit(
            imageSize: PetAsset.characterPixelSize(),
            in: CGSize(width: size, height: size)
        )
        ZStack {
            glint(at: leftGlint, in: fitted)
            glint(at: rightGlint, in: fitted)
            if isEditing {
                Text("拖动左右高光")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .offset(y: size / 2 - 14)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glint(at unit: CGPoint, in fitted: CGRect) -> some View {
        let socket = CGSize(
            width: fitted.width * PetMotion.eyeWidthFraction,
            height: fitted.height * PetMotion.eyeHeightFraction
        )
        let center = PetMotion.glintCenter(unit: unit, in: fitted, viewSize: size)
        let rest = CGSize(width: -socket.width * 0.14, height: socket.height * 0.12)
        let shift = CGSize(
            width: rest.width + look.eyeX * socket.width * 0.30,
            height: rest.height - look.eyeY * socket.height * 0.34
        )
        return ZStack {
            if isEditing {
                Circle()
                    .stroke(Color.white.opacity(0.95), lineWidth: 1.6)
                    .frame(width: PetMotion.glintHandleSize, height: PetMotion.glintHandleSize)
            }
            Ellipse()
                .fill(Color.white.opacity(isEditing ? 0.35 : 0.22))
                .frame(width: socket.width * 0.42, height: socket.height * 0.55)
                .offset(x: shift.width * 0.35, y: shift.height * 0.35)
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: max(3.2, size * 0.016), height: max(3.2, size * 0.016))
                .offset(x: shift.width - socket.width * 0.08, y: shift.height - socket.height * 0.12)
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: max(1.6, size * 0.008), height: max(1.6, size * 0.008))
                .offset(x: shift.width + socket.width * 0.10, y: shift.height + socket.height * 0.08)
        }
        .frame(width: isEditing ? PetMotion.glintHandleSize : socket.width, height: isEditing ? PetMotion.glintHandleSize : socket.height)
        .clipShape(Capsule())
        .position(x: center.x, y: center.y)
    }
}

private struct ResizeChrome: View {
    var petSize: CGFloat
    var windowLength: CGFloat

    var body: some View {
        let padding = PetSizing.chromePadding
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 1.6, dash: [6, 4]))
                .shadow(color: .black.opacity(0.35), radius: 0.5)
                .padding(padding - 1)

            ForEach(ResizeHandle.allCases, id: \.self) { handle in
                Circle()
                    .fill(Color.white)
                    .overlay {
                        Circle()
                            .stroke(Color(red: 0.12, green: 0.13, blue: 0.18), lineWidth: 1.4)
                    }
                    .frame(width: PetSizing.handleLength, height: PetSizing.handleLength)
                    .position(swiftUICorner(handle, padding: padding))
            }

            Text("拖动边角调整大小")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .offset(y: windowLength / 2 - 12)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func swiftUICorner(_ handle: ResizeHandle, padding: CGFloat) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: padding, y: padding)
        case .topRight:
            return CGPoint(x: padding + petSize, y: padding)
        case .bottomLeft:
            return CGPoint(x: padding, y: padding + petSize)
        case .bottomRight:
            return CGPoint(x: padding + petSize, y: padding + petSize)
        }
    }
}

