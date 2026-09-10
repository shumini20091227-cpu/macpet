import Foundation

public protocol BrowserOpening: Sendable {
    func open(_ url: URL)
}

public struct ChatGPTOpener: Sendable {
    public static let url = URL(string: "https://chatgpt.com")!

    public init() {}

    public func open(using browser: BrowserOpening) {
        browser.open(Self.url)
    }
}
