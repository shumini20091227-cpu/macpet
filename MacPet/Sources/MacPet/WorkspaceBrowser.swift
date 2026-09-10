import AppKit
import Foundation
import MacPetCore

struct WorkspaceBrowser: BrowserOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
