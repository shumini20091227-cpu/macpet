import CoreGraphics
import Foundation

public final class AppStore: @unchecked Sendable {
    private enum Key {
        static let foodCount = "foodCount"
        static let rewardedSessionIDs = "rewardedSessionIDs"
        static let foodsGrantedOnDay = "foodsGrantedOnDay"
        static let grantDay = "grantDay"
        static let windowOriginX = "windowOriginX"
        static let windowOriginY = "windowOriginY"
        static let hasWindowOrigin = "hasWindowOrigin"
        static let isWindowHidden = "isWindowHidden"
        static let petSize = "petSize"
        static let leftGlintX = "leftGlintX"
        static let leftGlintY = "leftGlintY"
        static let rightGlintX = "rightGlintX"
        static let rightGlintY = "rightGlintY"
    }

    private let defaults: UserDefaults
    private var cachedLedger: FoodLedger
    private var cachedWindowOrigin: CGPoint?
    private var cachedIsWindowHidden: Bool
    private var cachedPetSize: CGFloat
    private var cachedLeftGlint: CGPoint
    private var cachedRightGlint: CGPoint

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cachedLedger = Self.loadLedger(from: defaults)
        cachedWindowOrigin = Self.loadWindowOrigin(from: defaults)
        cachedIsWindowHidden = defaults.bool(forKey: Key.isWindowHidden)
        cachedPetSize = Self.loadPetSize(from: defaults)
        cachedLeftGlint = Self.loadGlint(
            from: defaults,
            xKey: Key.leftGlintX,
            yKey: Key.leftGlintY,
            fallback: PetMotion.leftEyeCenter
        )
        cachedRightGlint = Self.loadGlint(
            from: defaults,
            xKey: Key.rightGlintX,
            yKey: Key.rightGlintY,
            fallback: PetMotion.rightEyeCenter
        )
    }

    public var ledger: FoodLedger { cachedLedger }

    public func save(ledger: FoodLedger) {
        guard ledger != cachedLedger else { return }
        cachedLedger = ledger
        defaults.set(ledger.foodCount, forKey: Key.foodCount)
        defaults.set(Array(ledger.rewardedSessionIDs).sorted(), forKey: Key.rewardedSessionIDs)
        defaults.set(ledger.foodsGrantedOnDay, forKey: Key.foodsGrantedOnDay)
        defaults.set(ledger.grantDay.timeIntervalSince1970, forKey: Key.grantDay)
    }

    public var windowOrigin: CGPoint? {
        get { cachedWindowOrigin }
        set {
            guard newValue != cachedWindowOrigin else { return }
            cachedWindowOrigin = newValue
            if let newValue {
                defaults.set(true, forKey: Key.hasWindowOrigin)
                defaults.set(Double(newValue.x), forKey: Key.windowOriginX)
                defaults.set(Double(newValue.y), forKey: Key.windowOriginY)
            } else {
                defaults.set(false, forKey: Key.hasWindowOrigin)
            }
        }
    }

    public var isWindowHidden: Bool {
        get { cachedIsWindowHidden }
        set {
            guard newValue != cachedIsWindowHidden else { return }
            cachedIsWindowHidden = newValue
            defaults.set(newValue, forKey: Key.isWindowHidden)
        }
    }

    public var petSize: CGFloat {
        get { cachedPetSize }
        set {
            let size = PetSizing.clamp(newValue)
            guard size != cachedPetSize else { return }
            cachedPetSize = size
            defaults.set(Double(size), forKey: Key.petSize)
        }
    }

    public var leftGlint: CGPoint {
        get { cachedLeftGlint }
        set { setLeftGlint(newValue) }
    }

    public var rightGlint: CGPoint {
        get { cachedRightGlint }
        set { setRightGlint(newValue) }
    }

    public func resetGlints() {
        cachedLeftGlint = PetMotion.leftEyeCenter
        cachedRightGlint = PetMotion.rightEyeCenter
        defaults.removeObject(forKey: Key.leftGlintX)
        defaults.removeObject(forKey: Key.leftGlintY)
        defaults.removeObject(forKey: Key.rightGlintX)
        defaults.removeObject(forKey: Key.rightGlintY)
    }

    private func setLeftGlint(_ value: CGPoint) {
        let unit = PetMotion.clampGlintUnit(value)
        guard unit != cachedLeftGlint else { return }
        cachedLeftGlint = unit
        defaults.set(Double(unit.x), forKey: Key.leftGlintX)
        defaults.set(Double(unit.y), forKey: Key.leftGlintY)
    }

    private func setRightGlint(_ value: CGPoint) {
        let unit = PetMotion.clampGlintUnit(value)
        guard unit != cachedRightGlint else { return }
        cachedRightGlint = unit
        defaults.set(Double(unit.x), forKey: Key.rightGlintX)
        defaults.set(Double(unit.y), forKey: Key.rightGlintY)
    }

    private static func loadLedger(from defaults: UserDefaults) -> FoodLedger {
        FoodLedger(
            foodCount: defaults.integer(forKey: Key.foodCount),
            rewardedSessionIDs: Set(defaults.stringArray(forKey: Key.rewardedSessionIDs) ?? []),
            foodsGrantedOnDay: defaults.integer(forKey: Key.foodsGrantedOnDay),
            grantDay: Date(timeIntervalSince1970: defaults.object(forKey: Key.grantDay) as? TimeInterval ?? 0)
        )
    }

    private static func loadWindowOrigin(from defaults: UserDefaults) -> CGPoint? {
        guard defaults.bool(forKey: Key.hasWindowOrigin) else { return nil }
        return CGPoint(
            x: defaults.double(forKey: Key.windowOriginX),
            y: defaults.double(forKey: Key.windowOriginY)
        )
    }

    private static func loadPetSize(from defaults: UserDefaults) -> CGFloat {
        guard defaults.object(forKey: Key.petSize) != nil else {
            return PetSizing.defaultSize
        }
        return PetSizing.clamp(CGFloat(defaults.double(forKey: Key.petSize)))
    }

    private static func loadGlint(
        from defaults: UserDefaults,
        xKey: String,
        yKey: String,
        fallback: CGPoint
    ) -> CGPoint {
        guard defaults.object(forKey: xKey) != nil, defaults.object(forKey: yKey) != nil else {
            return fallback
        }
        return PetMotion.clampGlintUnit(
            CGPoint(x: defaults.double(forKey: xKey), y: defaults.double(forKey: yKey))
        )
    }
}
