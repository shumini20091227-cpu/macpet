import CoreGraphics

public struct AppSettings: Equatable, Sendable {
    public var clickDragThreshold: CGFloat

    public init(clickDragThreshold: CGFloat = 5) {
        self.clickDragThreshold = clickDragThreshold
    }
}
