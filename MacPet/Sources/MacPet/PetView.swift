import AppKit
import MacPetCore
import Observation
import SwiftUI

@MainActor
@Observable
final class PetDisplay {
    var state: PetState = .rest
    var foodCount: Int = 0
    var eatStartedAt: Date?
    var eatDuration: TimeInterval = 2.6
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
                : isResizing ? "拖动边角调整大小，右键完成调整" : "单击打开 ChatGPT，专注中双击查看时长，右键喂食或退出"
        )
    }

    private func canvas(at date: Date) -> some View {
        let elapsed = date.timeIntervalSinceReferenceDate
        let pose = currentPose(elapsed: elapsed, now: date)
        let tomatoPoint = PetMotion.tomatoOffset(travel: pose.tomatoTravel, size: size)

        return ZStack {
            ZStack {
                character()
                    .frame(width: size, height: size)
                    .overlay {
                        if !usesStudyArt {
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

            if display.state == .study, !usesStudyArt {
                StudyPageOverlay(flip: reduceMotion ? 0 : PetMotion.studyPageFlip(elapsed: elapsed), size: size)
            }

            if display.state == .eat, pose.tomatoOpacity > 0.02 {
                TomatoView()
                    .frame(width: size * 0.17, height: size * 0.17)
                    .rotationEffect(.degrees(pose.tomatoRotation))
                    .scaleEffect(pose.tomatoScale)
                    .opacity(pose.tomatoOpacity)
                    .offset(x: tomatoPoint.x, y: tomatoPoint.y)
                    .accessibilityHidden(true)
            }

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
        if isEditingGlints {
            return VisualPose(
                scaleX: 1,
                scaleY: 1,
                tilt: 0,
                lookTilt: 0,
                offsetX: 0,
                offsetY: 0,
                tomatoTravel: 0,
                tomatoScale: 1,
                tomatoOpacity: 0,
                tomatoRotation: 0
            )
        }
        let damp: CGFloat = reduceMotion ? 0.55 : 1

        switch display.state {
        case .rest:
            let wave = PetMotion.breathScaleY(elapsed: elapsed) - 1
            return VisualPose(
                scaleX: 1 + (PetMotion.breathScaleX(elapsed: elapsed) - 1) * damp,
                scaleY: 1 + wave * damp,
                tilt: Double(1.1 * damp) * sin(elapsed * 1.15),
                lookTilt: display.look.headTilt * Double(damp),
                offsetX: display.look.offsetX * damp,
                offsetY: -PetMotion.breathLift(elapsed: elapsed) * damp + display.look.offsetY * damp,
                tomatoTravel: 0,
                tomatoScale: 1,
                tomatoOpacity: 0,
                tomatoRotation: 0
            )
        case .study:
            let tilt = PetMotion.studyTiltDegrees(elapsed: elapsed)
            let base: Double = -4.5
            let nod = (tilt - base) * Double(damp)
            return VisualPose(
                scaleX: 1,
                scaleY: 1,
                tilt: base + nod,
                lookTilt: display.look.headTilt * Double(damp),
                offsetX: display.look.offsetX * damp,
                offsetY: 1.6 * damp * CGFloat(sin(2 * Double.pi * elapsed / PetMotion.studyPeriod)) + display.look.offsetY * damp,
                tomatoTravel: 0,
                tomatoScale: 1,
                tomatoOpacity: 0,
                tomatoRotation: 0
            )
        case .eat:
            let eatElapsed = display.eatStartedAt.map { now.timeIntervalSince($0) } ?? 0
            let progress = PetMotion.eatProgress(elapsed: eatElapsed, duration: display.eatDuration)
            let eat = PetMotion.eatPose(progress: progress)
            return VisualPose(
                scaleX: 1,
                scaleY: 1 + (eat.characterScaleY - 1) * damp,
                tilt: -3,
                lookTilt: display.look.headTilt * Double(damp),
                offsetX: display.look.offsetX * damp,
                offsetY: -eat.characterOffsetY * damp + display.look.offsetY * damp,
                tomatoTravel: eat.tomatoTravel,
                tomatoScale: eat.tomatoScale,
                tomatoOpacity: eat.tomatoOpacity,
                tomatoRotation: reduceMotion ? 0 : eat.tomatoRotation
            )
        }
    }

    private var accessibilityValue: String {
        switch display.state {
        case .rest: return isEditingGlints ? "调整高光，食物 \(display.foodCount)" : isResizing ? "调整大小，食物 \(display.foodCount)" : "休息，食物 \(display.foodCount)"
        case .study: return isEditingGlints ? "调整高光，食物 \(display.foodCount)" : isResizing ? "调整大小，食物 \(display.foodCount)" : "看书，食物 \(display.foodCount)"
        case .eat: return isEditingGlints ? "调整高光，食物 \(display.foodCount)" : isResizing ? "调整大小，食物 \(display.foodCount)" : "吃番茄，食物 \(display.foodCount)"
        }
    }

    private var usesStudyArt: Bool {
        PetAsset.usesStudyArt(state: display.state, isEditingGlints: isEditingGlints)
    }

    @ViewBuilder
    private func character() -> some View {
        if let image = PetAsset.displayedImage(state: display.state, isEditingGlints: isEditingGlints) {
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
    var tomatoTravel: CGFloat
    var tomatoScale: CGFloat
    var tomatoOpacity: CGFloat
    var tomatoRotation: Double
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

private struct StudyPageOverlay: View {
    var flip: Double
    var size: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color(red: 0.15, green: 0.16, blue: 0.2), lineWidth: 1.5)
                }

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(red: 0.97, green: 0.97, blue: 0.94))
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(Color(red: 0.55, green: 0.58, blue: 0.62))
                                .frame(height: 1.5)
                        }
                    }
                    .padding(.horizontal, 5)
                }
                .rotation3DEffect(
                    .degrees(flip * 105),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.55
                )
        }
        .frame(width: size * 0.30, height: size * 0.18)
        .offset(x: -size * 0.03, y: size * 0.22)
        .accessibilityHidden(true)
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

private struct TomatoView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.86, green: 0.22, blue: 0.20))
                .overlay {
                    Circle()
                        .stroke(Color(red: 0.12, green: 0.13, blue: 0.18), lineWidth: 2.4)
                }
                .overlay(alignment: .topLeading) {
                    Ellipse()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 8, height: 11)
                        .offset(x: 7, y: 9)
                }

            TomatoCalyx()
                .fill(Color(red: 0.27, green: 0.62, blue: 0.28))
                .overlay {
                    TomatoCalyx()
                        .stroke(Color(red: 0.12, green: 0.13, blue: 0.18), lineWidth: 1.1)
                }
                .frame(width: 16, height: 10)
                .offset(y: -13)

            Capsule()
                .fill(Color(red: 0.36, green: 0.24, blue: 0.14))
                .frame(width: 2.4, height: 6)
                .offset(y: -17)
        }
    }
}

private struct TomatoCalyx: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        path.move(to: CGPoint(x: midX, y: midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: rect.minX + 2, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: midX, y: midY),
            control: CGPoint(x: midX - 2, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - 2, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: midX, y: midY),
            control: CGPoint(x: midX + 2, y: rect.maxY)
        )
        return path
    }
}
