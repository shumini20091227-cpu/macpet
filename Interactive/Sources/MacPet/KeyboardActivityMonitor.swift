import AppKit
import CoreGraphics

// A listen-only tap receives no text: only a key-down signal is forwarded.
@MainActor
final class KeyboardActivityMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var idle: Timer?
    private let changed: (Bool) -> Void
    init(changed: @escaping (Bool) -> Void) { self.changed = changed }

    @discardableResult func start(prompt: Bool) -> Bool {
        if tap != nil { return true }
        guard CGPreflightListenEventAccess() || (prompt && CGRequestListenEventAccess()) else { return false }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, context in
                if let context {
                    MainActor.assumeIsolated {
                        let owner = Unmanaged<KeyboardActivityMonitor>.fromOpaque(context).takeUnretainedValue()
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                        } else if type == .keyDown { owner.activity() }
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: context) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
    private func activity() {
        changed(true)
        idle?.invalidate()
        idle = Timer(timeInterval: 0.5, target: self, selector: #selector(restore), userInfo: nil, repeats: false)
        RunLoop.main.add(idle!, forMode: .common)
    }
    @objc private func restore() { idle = nil; changed(false) }
    func stop() {
        idle?.invalidate(); idle = nil
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
}
