import CoreGraphics
import Foundation

public final class PetRuntime: @unchecked Sendable {
    public let settings: AppSettings
    public var windowOrigin: CGPoint? {
        get { store.windowOrigin }
        set { store.windowOrigin = newValue }
    }
    public var isWindowHidden: Bool {
        get { store.isWindowHidden }
        set { store.isWindowHidden = newValue }
    }
    public var petSize: CGFloat {
        get { store.petSize }
        set { store.petSize = newValue }
    }
    public var leftGlint: CGPoint {
        get { store.leftGlint }
        set { store.leftGlint = newValue }
    }
    public var rightGlint: CGPoint {
        get { store.rightGlint }
        set { store.rightGlint = newValue }
    }

    public func resetGlints() {
        store.resetGlints()
    }

    private let store: AppStore
    private let browser: BrowserOpening

    public init(store: AppStore, settings: AppSettings = AppSettings(), browser: BrowserOpening) {
        self.store = store
        self.settings = settings
        self.browser = browser
    }

    public func handleLeftClick() {
        ChatGPTOpener().open(using: browser)
    }

    public func persistWindowOrigin(_ origin: CGPoint) { store.windowOrigin = origin }
    public func hideWindow() { store.isWindowHidden = true }
    public func showWindow() { store.isWindowHidden = false }
}
