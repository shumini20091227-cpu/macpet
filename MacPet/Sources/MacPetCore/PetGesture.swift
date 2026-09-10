import CoreGraphics

public enum PetGesture: Equatable, Sendable {
    case click
    case drag
}

public func classifyPetGesture(translation: CGSize, threshold: CGFloat) -> PetGesture {
    hypot(translation.width, translation.height) > threshold ? .drag : .click
}
