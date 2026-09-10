import CoreGraphics
import Foundation

public struct AppSettings: Equatable, Sendable {
    public var focusMinutesPerFood: Int
    public var dailyFoodCap: Int
    public var minimumValidSessionMinutes: Int
    public var eatAnimationDuration: TimeInterval
    public var clickDragThreshold: CGFloat
    public var petSize: CGFloat

    public init(
        focusMinutesPerFood: Int = 25,
        dailyFoodCap: Int = 12,
        minimumValidSessionMinutes: Int = 5,
        eatAnimationDuration: TimeInterval = 2.6,
        clickDragThreshold: CGFloat = 5,
        petSize: CGFloat = 220
    ) {
        self.focusMinutesPerFood = focusMinutesPerFood
        self.dailyFoodCap = dailyFoodCap
        self.minimumValidSessionMinutes = minimumValidSessionMinutes
        self.eatAnimationDuration = eatAnimationDuration
        self.clickDragThreshold = clickDragThreshold
        self.petSize = petSize
    }
}
