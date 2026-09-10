import AppKit
import MacPetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: PetRuntime!
    private var petWindow: PetWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let mock = MockFocusPomoAdapter()
        runtime = PetRuntime(
            store: AppStore(defaults: .standard),
            adapter: mock,
            mock: mock,
            browser: WorkspaceBrowser()
        )
        petWindow = PetWindowController(runtime: runtime)
        if runtime.isWindowHidden {
            petWindow.hidePet()
        } else {
            petWindow.showPet()
        }
        NSLog("MacPet launched, hidden=%@", runtime.isWindowHidden ? "yes" : "no")
        installAppMenu()
        Task {
            await runtime.syncFromAdapter()
        }
    }

    private func installAppMenu() {
        let appName = "MacPet"
        let appMenu = NSMenu()
        let refreshItem = appMenu.addItem(withTitle: "刷新", action: #selector(PetWindowController.refreshPet), keyEquivalent: "r")
        refreshItem.target = petWindow
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        petWindow.revealFromDock()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        petWindow.persistNow()
    }
}
