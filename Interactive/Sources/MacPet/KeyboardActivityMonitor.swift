import AppKit
import CoreGraphics

// A listen-only tap receives no text: only a key-down signal is forwarded.
@MainActor
final class KeyboardActivityMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var idle: Timer?
    private var eventsReceived = 0
    private func report(_ status: String) {
        UserDefaults.standard.set(status, forKey: "keyboardDiagnosticStatus")
        UserDefaults.standard.set(eventsReceived, forKey: "keyboardDiagnosticEventCount")
    }
    private var desired = false
    private var recovery: Timer?
    private var observers: [NSObjectProtocol] = []
    private var pendingActivity = false
    var isListening: Bool { tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }
    private let changed: (Bool) -> Void
    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
        for name in [NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconnect() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconnect() }
            })
        }
    }
    private func reconnect() {
        guard desired else { return }
        _ = start(prompt: false)
    }
    private func retryLater() {
        guard recovery == nil else { return }
        recovery = Timer(timeInterval: 2, target: self, selector: #selector(retry), userInfo: nil, repeats: false)
        RunLoop.main.add(recovery!, forMode: .common)
    }
    @objc private func retry() { recovery = nil; reconnect() }


    @discardableResult func start(prompt: Bool) -> Bool {
        desired = true
        if isListening { return true }
        disconnect()

        guard CGPreflightListenEventAccess() || (prompt && CGRequestListenEventAccess()) else { report("permission-denied"); retryLater(); return false }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, context in
                if let context {
                    MainActor.assumeIsolated {
                        let owner = Unmanaged<KeyboardActivityMonitor>.fromOpaque(context).takeUnretainedValue()
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                        } else if type == .keyDown, !owner.pendingActivity {
                            owner.pendingActivity = true
                            // Decode/switch expressions outside the event-tap callback.
                            DispatchQueue.main.async { [weak owner] in
                                guard let owner else { return }
                                owner.pendingActivity = false
                                if owner.desired { owner.activity() }
                            }
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: context) else { report("tap-creation-failed"); retryLater(); return false }
        recovery?.invalidate(); recovery = nil
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        report("listening")
        return true
    }
    private func activity() {
        eventsReceived += 1
        if eventsReceived == 1 { report("receiving-events") }
        changed(true)
        idle?.invalidate()
        idle = Timer(timeInterval: 0.5, target: self, selector: #selector(restore), userInfo: nil, repeats: false)
        RunLoop.main.add(idle!, forMode: .common)
    }
    @objc private func restore() { idle = nil; changed(false) }
    func stop() {
        desired = false
        recovery?.invalidate(); recovery = nil
        disconnect()
        changed(false)
    }
    private func disconnect() {
        idle?.invalidate(); idle = nil
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
}
