import CoreGraphics
import Foundation

public enum ResizeHandle: String, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

public enum PetSizing {
    public static let defaultSize: CGFloat = 220
    public static let minSize: CGFloat = 100
    public static let maxSize: CGFloat = 560
    public static let chromePadding: CGFloat = 22
    public static let handleLength: CGFloat = 12
    public static let handleHit: CGFloat = 28

    public static func clamp(_ size: CGFloat) -> CGFloat {
        min(max(size, minSize), maxSize)
    }

    public static func windowLength(petSize: CGFloat, isResizing: Bool) -> CGFloat {
        isResizing ? petSize + chromePadding * 2 : petSize
    }

    public static func size(
        original: CGFloat,
        translation: CGSize,
        handle: ResizeHandle
    ) -> CGFloat {
        let projected: CGFloat
        switch handle {
        case .topRight:
            projected = translation.width + translation.height
        case .topLeft:
            projected = -translation.width + translation.height
        case .bottomRight:
            projected = translation.width - translation.height
        case .bottomLeft:
            projected = -translation.width - translation.height
        }
        return clamp(original + projected)
    }

    public static func handleFrame(_ handle: ResizeHandle, petSize: CGFloat) -> CGRect {
        let corner: CGPoint
        switch handle {
        case .bottomLeft:
            corner = CGPoint(x: chromePadding, y: chromePadding)
        case .bottomRight:
            corner = CGPoint(x: chromePadding + petSize, y: chromePadding)
        case .topLeft:
            corner = CGPoint(x: chromePadding, y: chromePadding + petSize)
        case .topRight:
            corner = CGPoint(x: chromePadding + petSize, y: chromePadding + petSize)
        }
        return CGRect(
            x: corner.x - handleHit / 2,
            y: corner.y - handleHit / 2,
            width: handleHit,
            height: handleHit
        )
    }

    public static func handle(at point: CGPoint, petSize: CGFloat) -> ResizeHandle? {
        ResizeHandle.allCases.first { handleFrame($0, petSize: petSize).contains(point) }
    }
}
