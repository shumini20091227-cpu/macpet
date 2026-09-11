import Foundation

public struct FoodLedger: Equatable, Sendable {
    public var foodCount: Int
    public var rewardedSessionIDs: Set<String>
    public var foodsGrantedOnDay: Int
    public var grantDay: Date

    public init(
        foodCount: Int = 0,
        rewardedSessionIDs: Set<String> = [],
        foodsGrantedOnDay: Int = 0,
        grantDay: Date = Date()
    ) {
        self.foodCount = foodCount
        self.rewardedSessionIDs = rewardedSessionIDs
        self.foodsGrantedOnDay = foodsGrantedOnDay
        self.grantDay = grantDay
    }
}

public struct FoodEngine: Sendable {
    public var settings: AppSettings

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    public func apply(
        sessions: [FocusSession],
        ledger: FoodLedger,
        now: Date,
        calendar: Calendar
    ) -> FoodLedger {
        var next = ledger
        if !calendar.isDate(now, inSameDayAs: next.grantDay) {
            next.foodsGrantedOnDay = 0
            next.grantDay = calendar.startOfDay(for: now)
        }

        for session in sessions {
            if next.rewardedSessionIDs.contains(session.id) {
                continue
            }
            if session.durationMinutes < settings.minimumValidSessionMinutes {
                continue
            }

            let rawFood = session.durationMinutes / settings.focusMinutesPerFood
            let remaining = max(0, settings.dailyFoodCap - next.foodsGrantedOnDay)
            let granted = min(rawFood, remaining)
            next.foodCount += granted
            next.foodsGrantedOnDay += granted
            next.rewardedSessionIDs.insert(session.id)
        }

        return next
    }

    public func consumeFood(_ ledger: inout FoodLedger) -> Bool {
        guard ledger.foodCount > 0 else { return false }
        ledger.foodCount -= 1
        return true
    }
}
