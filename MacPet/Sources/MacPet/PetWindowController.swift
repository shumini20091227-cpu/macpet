import AppKit
import MacPetCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PetWindowController: NSWindowController, NSWindowDelegate {
    private let runtime: PetRuntime
    private let display = PetDisplay()
    private var hostingView: ClearHostingView<PetView>
    private var motionTimer: Timer?
    private(set) var isResizing = false
    private(set) var isEditingGlints = false
    private var reduceMotion: Bool
    private var isDisplayAsleep = false
    private var isScreenLocked = false
    private var lastMouseLocation: CGPoint?
    private var lastLookTarget = LookPose.zero
    private var persistWork: DispatchWorkItem?
    private var energyObservers: [NSObjectProtocol] = []
    private var isWindowOccluded = false
    private var bannerHideWork: DispatchWorkItem?

    init(runtime: PetRuntime) {
        self.runtime = runtime
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let root = PetView(
            display: display,
            size: runtime.petSize,
            reduceMotion: reduceMotion
        )
        hostingView = ClearHostingView(rootView: root)

        let size = runtime.petSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.isExcludedFromWindowsMenu = true
        panel.title = "MacPet"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = false
        panel.isRestorable = false
        panel.animationBehavior = .none

        let container = PetContainerView(frame: NSRect(origin: .zero, size: NSSize(width: size, height: size)))
        container.controller = self
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container

        restorePosition(for: panel)
        refreshDisplay()
        observeEnergySignals()
        updateMotionClock()

        runtime.onChange = { [weak self] in
            Task { @MainActor in
                self?.refreshDisplay()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPet() {
        runtime.showWindow()
        keepVisibleOverSpaces()
        window?.orderFrontRegardless()
        isWindowOccluded = false
        runtime.refreshFocus()
        updateMotionClock()
    }

    func hidePet() {
        if isResizing {
            let footprint = petFootprint()
            isResizing = false
            window?.acceptsMouseMovedEvents = false
            layoutWindow(footMidX: footprint.midX, footMinY: footprint.minY)
        }
        isEditingGlints = false
        persistNow()
        runtime.hideWindow()
        window?.orderOut(nil)
        updateMotionClock()
    }

    func revealFromDock() {
        runtime.showWindow()
        keepVisibleOverSpaces()
        window?.makeKeyAndOrderFront(nil)
        isWindowOccluded = false
        runtime.refreshFocus()
        updateMotionClock()
    }

    var isFocusing: Bool { runtime.isFocusing }

    func handleLeftClick() {
        runtime.handleLeftClick()
    }

    func handleInspectFocus() {
        guard let text = runtime.focusDurationText() else { return }
        showBanner(text)
    }

    private func showBanner(_ text: String) {
        display.banner = text
        bannerHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.display.banner = nil
        }
        bannerHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    func handleDrag(to origin: NSPoint) {
        window?.setFrameOrigin(origin)
    }

    func persistCurrentOrigin() {
        guard let window else { return }
        let padding = isResizing ? PetSizing.chromePadding : 0
        runtime.persistWindowOrigin(
            NSPoint(x: window.frame.minX + padding, y: window.frame.minY + padding)
        )
    }

    var currentPetSize: CGFloat { runtime.petSize }
    var displayedPetState: PetState { runtime.petState }

    func applyPetSize(_ size: CGFloat) {
        let footprint = petFootprint()
        runtime.petSize = size
        layoutWindow(footMidX: footprint.midX, footMinY: footprint.minY)
        schedulePersist()
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let feedTitle = "喂番茄（\(runtime.foodCount)）"
        let feedItem = menu.addItem(withTitle: feedTitle, action: #selector(feedPet), keyEquivalent: "")
        feedItem.target = self
        feedItem.isEnabled = runtime.foodCount > 0 && runtime.petState != .eat

        let focusTitle = runtime.isFocusing ? "停止专注" : "开始专注"
        let focusItem = menu.addItem(withTitle: focusTitle, action: #selector(toggleFocus), keyEquivalent: "")
        focusItem.target = self

        menu.addItem(.separator())

        let resizeItem = menu.addItem(
            withTitle: isResizing ? "完成调整" : "调整大小",
            action: #selector(toggleResizeMode),
            keyEquivalent: ""
        )
        resizeItem.target = self

        let glintItem = menu.addItem(
            withTitle: isEditingGlints ? "完成高光" : "调整高光",
            action: #selector(toggleGlintEditor),
            keyEquivalent: ""
        )
        glintItem.target = self
        if isEditingGlints {
            let resetItem = menu.addItem(withTitle: "恢复默认高光", action: #selector(resetGlints), keyEquivalent: "")
            resetItem.target = self
        }

        let replaceItem = menu.addItem(withTitle: "更换形象", action: #selector(replaceCharacter), keyEquivalent: "")
        replaceItem.target = self
        let restoreItem = menu.addItem(withTitle: "恢复默认形象", action: #selector(restoreDefaultCharacter), keyEquivalent: "")
        restoreItem.target = self
        restoreItem.isEnabled = PetAsset.hasCustomCharacter()

        let refreshItem = menu.addItem(withTitle: "刷新", action: #selector(refreshPet), keyEquivalent: "r")
        refreshItem.target = self

        let hideItem = menu.addItem(withTitle: "隐藏", action: #selector(hidePetAction), keyEquivalent: "")
        hideItem.target = self

        let quitItem = menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        return menu
    }

    func gestureThreshold() -> CGFloat {
        runtime.settings.clickDragThreshold
    }

    @objc private func feedPet() {
        _ = runtime.feed()
        refreshDisplay()
    }

    @objc private func toggleFocus() {
        let foodBefore = runtime.foodCount
        let wasFocusing = runtime.isFocusing
        runtime.toggleFocus()
        refreshDisplay()
        if wasFocusing {
            let gained = runtime.foodCount - foodBefore
            if gained > 0 {
                showBanner(gained == 1 ? "获得 1 个番茄" : "获得 \(gained) 个番茄")
            }
        }
    }

    @objc private func toggleResizeMode() {
        if isEditingGlints { isEditingGlints = false }
        let footprint = petFootprint()
        isResizing.toggle()
        window?.acceptsMouseMovedEvents = isResizing
        layoutWindow(footMidX: footprint.midX, footMinY: footprint.minY)
    }

    @objc private func toggleGlintEditor() {
        if isResizing {
            let footprint = petFootprint()
            isResizing = false
            window?.acceptsMouseMovedEvents = false
            layoutWindow(footMidX: footprint.midX, footMinY: footprint.minY)
        }
        isEditingGlints.toggle()
        display.look = .zero
        lastMouseLocation = nil
        lastLookTarget = .zero
        if let content = window?.contentView {
            window?.invalidateCursorRects(for: content)
        }
        updateMotionClock()
        if motionTimer == nil {
            motionTick()
        }
    }

    @objc private func resetGlints() {
        runtime.resetGlints()
        motionTick()
    }

    @objc private func replaceCharacter() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "更换形象"
        panel.message = "选择一张透明背景的 PNG，会替换当前形象"
        panel.prompt = "使用"
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard NSImage(contentsOf: url) != nil else { return }
        do {
            try PetCharacterStore.install(from: url, into: PetAsset.supportDirectory)
        } catch {
            return
        }
        applyLoadedCharacter()
    }

    @objc private func restoreDefaultCharacter() {
        try? PetCharacterStore.removeCustom(in: PetAsset.supportDirectory)
        applyLoadedCharacter()
    }

    private func applyLoadedCharacter() {
        isEditingGlints = false
        runtime.resetGlints()
        PetAsset.reload()
        if let content = window?.contentView {
            window?.invalidateCursorRects(for: content)
        }
        motionTick()
    }

    func applyGlint(_ slot: GlintSlot, toAppKitPoint point: CGPoint) {
        let swift = petLocalSwiftPoint(fromAppKit: point)
        let unit = PetMotion.unitPoint(
            fromView: swift,
            imageSize: PetAsset.characterPixelSize(),
            viewSize: runtime.petSize
        )
        switch slot {
        case .left: runtime.leftGlint = unit
        case .right: runtime.rightGlint = unit
        }
        motionTick()
    }

    func glintSlot(atAppKit point: CGPoint) -> GlintSlot? {
        guard isEditingGlints else { return nil }
        let swift = petLocalSwiftPoint(fromAppKit: point)
        let imageSize = PetAsset.characterPixelSize()
        let viewSize = runtime.petSize
        let left = PetMotion.glintCenter(unit: runtime.leftGlint, imageSize: imageSize, viewSize: viewSize)
        let right = PetMotion.glintCenter(unit: runtime.rightGlint, imageSize: imageSize, viewSize: viewSize)
        let hit = PetMotion.glintHandleSize
        let dLeft = hypot(swift.x - left.x, swift.y - left.y)
        let dRight = hypot(swift.x - right.x, swift.y - right.y)
        if dLeft <= hit, dLeft <= dRight { return .left }
        if dRight <= hit { return .right }
        return nil
    }

    private func petLocalSwiftPoint(fromAppKit point: CGPoint) -> CGPoint {
        let padding = isResizing ? PetSizing.chromePadding : 0
        let local = CGPoint(x: point.x - padding, y: point.y - padding)
        return CGPoint(x: local.x, y: runtime.petSize - local.y)
    }

    @objc func refreshPet() {
        persistNow()
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func hidePetAction() {
        hidePet()
    }

    @objc private func quitApp() {
        persistNow()
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        persistNow()
    }

    private func keepVisibleOverSpaces() {
        guard let panel = window as? NSPanel else { return }
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    private func petFootprint() -> (midX: CGFloat, minY: CGFloat) {
        guard let frame = window?.frame else { return (0, 0) }
        let padding = isResizing ? PetSizing.chromePadding : 0
        return (frame.midX, frame.minY + padding)
    }

    private func layoutWindow(footMidX: CGFloat, footMinY: CGFloat) {
        guard let window else { return }
        let padding = isResizing ? PetSizing.chromePadding : 0
        let length = PetSizing.windowLength(petSize: runtime.petSize, isResizing: isResizing)
        window.setFrame(
            NSRect(
                x: footMidX - length / 2,
                y: footMinY - padding,
                width: length,
                height: length
            ),
            display: true
        )
        if let content = window.contentView {
            window.invalidateCursorRects(for: content)
        }
        motionTick()
    }

    private func restorePosition(for panel: NSPanel) {
        if let origin = runtime.windowOrigin {
            panel.setFrameOrigin(origin)
            return
        }
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.minX + 48, y: visible.minY + 48))
        }
    }

    private func refreshDisplay() {
        display.state = runtime.petState
        display.foodCount = runtime.foodCount
        display.eatStartedAt = runtime.eatStartedAt
        display.eatDuration = runtime.settings.eatAnimationDuration
    }

    private func observeEnergySignals() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observeEnergy(workspace, NSWorkspace.screensDidSleepNotification) {
            $0.isDisplayAsleep = true
            $0.updateMotionClock()
        }
        observeEnergy(workspace, NSWorkspace.screensDidWakeNotification) {
            $0.isDisplayAsleep = false
            $0.updateMotionClock()
        }
        observeEnergy(workspace, NSWorkspace.willSleepNotification) {
            $0.isDisplayAsleep = true
            $0.updateMotionClock()
        }
        observeEnergy(workspace, NSWorkspace.didWakeNotification) {
            $0.isDisplayAsleep = false
            $0.updateMotionClock()
        }
        observeEnergy(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
            let next = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            guard next != $0.reduceMotion else { return }
            $0.reduceMotion = next
            $0.motionTick()
        }
        observeEnergy(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification, object: window) {
            $0.isWindowOccluded = $0.window?.occlusionState.contains(.visible) != true
            $0.updateMotionClock()
        }
        observeEnergy(distributed, NSNotification.Name("com.apple.screenIsLocked")) {
            $0.isScreenLocked = true
            $0.updateMotionClock()
        }
        observeEnergy(distributed, NSNotification.Name("com.apple.screenIsUnlocked")) {
            $0.isScreenLocked = false
            $0.updateMotionClock()
        }
    }

    private func observeEnergy(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: Any? = nil,
        _ body: @escaping @MainActor (PetWindowController) -> Void
    ) {
        energyObservers.append(
            center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    body(self)
                }
            }
        )
    }

    private func updateMotionClock() {
        if PetEnergy.shouldDriveFrames(
            isWindowOnscreen: window?.isVisible == true,
            isWindowOccluded: isWindowOccluded,
            isDisplayAsleep: isDisplayAsleep,
            isScreenLocked: isScreenLocked,
            isPoseFrozen: isEditingGlints
        ) {
            startMotionClock()
        } else {
            stopMotionClock()
        }
    }

    private func startMotionClock() {
        guard motionTimer == nil else { return }
        let timer = Timer(
            timeInterval: PetEnergy.motionFrameInterval,
            target: self,
            selector: #selector(motionTick),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = PetEnergy.motionTimerTolerance
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
        motionTick()
    }

    private func stopMotionClock() {
        motionTimer?.invalidate()
        motionTimer = nil
    }

    private func schedulePersist() {
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistCurrentOrigin()
        }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func persistNow() {
        persistWork?.cancel()
        persistWork = nil
        persistCurrentOrigin()
    }

    @objc private func motionTick() {
        updateLook()
        display.tick = Date()
        hostingView.rootView = PetView(
            display: display,
            size: runtime.petSize,
            reduceMotion: reduceMotion,
            isResizing: isResizing,
            isEditingGlints: isEditingGlints,
            leftGlint: runtime.leftGlint,
            rightGlint: runtime.rightGlint
        )
    }

    private func updateLook() {
        if isEditingGlints {
            display.look = .zero
            lastMouseLocation = nil
            lastLookTarget = .zero
            return
        }
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        if let lastMouseLocation,
           !PetEnergy.mouseMoved(lastMouseLocation, mouse),
           PetEnergy.lookHasSettled(display.look, lastLookTarget) {
            return
        }
        lastMouseLocation = mouse
        let padding = isResizing ? PetSizing.chromePadding : 0
        let petSize = runtime.petSize
        let petCenter = CGPoint(
            x: window.frame.midX,
            y: window.frame.minY + padding + petSize * 0.58
        )
        let target = PetMotion.lookPose(
            mouse: mouse,
            petCenter: petCenter,
            petSize: petSize
        ).scaled(by: PetMotion.lookWeight(state: display.state, isResizing: isResizing))
        lastLookTarget = target
        if PetEnergy.lookHasSettled(display.look, target) {
            display.look = target
            return
        }
        display.look = PetMotion.blendLook(display.look, toward: target, factor: PetMotion.lookBlend)
    }
}

@MainActor
final class PetContainerView: NSView {
    weak var controller: PetWindowController?
    private var mouseDownScreen: NSPoint?
    private var windowOriginAtDown: NSPoint?
    private var isDragging = false
    private var activeHandle: ResizeHandle?
    private var sizeAtDown: CGFloat?
    private var activeGlint: GlintSlot?
    private var pendingClick: DispatchWorkItem?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if handle(at: point) != nil { return self }
        if controller?.glintSlot(atAppKit: point) != nil { return self }
        guard isCharacterPixel(at: point) else { return nil }
        return self
    }

    override func resetCursorRects() {
        discardCursorRects()
        guard let controller else { return }
        if controller.isResizing {
            let petSize = controller.currentPetSize
            addCursorRect(PetSizing.handleFrame(.topLeft, petSize: petSize), cursor: .crosshair)
            addCursorRect(PetSizing.handleFrame(.topRight, petSize: petSize), cursor: .crosshair)
            addCursorRect(PetSizing.handleFrame(.bottomLeft, petSize: petSize), cursor: .crosshair)
            addCursorRect(PetSizing.handleFrame(.bottomRight, petSize: petSize), cursor: .crosshair)
        }
        if controller.isEditingGlints {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreen = NSEvent.mouseLocation
        windowOriginAtDown = window?.frame.origin
        isDragging = false
        activeHandle = handle(at: convert(event.locationInWindow, from: nil))
        activeGlint = controller?.glintSlot(atAppKit: convert(event.locationInWindow, from: nil))
        sizeAtDown = controller?.currentPetSize
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownScreen, let controller else { return }
        let current = NSEvent.mouseLocation
        let translation = CGSize(
            width: current.x - mouseDownScreen.x,
            height: current.y - mouseDownScreen.y
        )
        if let activeGlint {
            isDragging = true
            controller.applyGlint(activeGlint, toAppKitPoint: convert(event.locationInWindow, from: nil))
            return
        }
        if let activeHandle, let sizeAtDown {
            isDragging = true
            controller.applyPetSize(PetSizing.size(original: sizeAtDown, translation: translation, handle: activeHandle))
            return
        }
        guard let windowOriginAtDown else { return }
        if controller.isEditingGlints { return }
        if classifyPetGesture(translation: translation, threshold: controller.gestureThreshold()) == .drag {
            isDragging = true
            let origin = NSPoint(
                x: windowOriginAtDown.x + translation.width,
                y: windowOriginAtDown.y + translation.height
            )
            controller.handleDrag(to: origin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            controller?.persistNow()
        } else if controller?.isResizing != true, controller?.isEditingGlints != true {
            handlePetClick(event)
        }
        mouseDownScreen = nil
        windowOriginAtDown = nil
        isDragging = false
        activeHandle = nil
        activeGlint = nil
        sizeAtDown = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let controller, controller.isResizing else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        controller.applyPetSize(controller.currentPetSize + delta)
    }

    override func magnify(with event: NSEvent) {
        guard let controller, controller.isResizing else { return }
        controller.applyPetSize(controller.currentPetSize * (1 + event.magnification))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.makeContextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func handlePetClick(_ event: NSEvent) {
        if event.clickCount >= 2, controller?.isFocusing == true {
            pendingClick?.cancel()
            pendingClick = nil
            controller?.handleInspectFocus()
            return
        }
        guard event.clickCount == 1 else { return }
        if controller?.isFocusing == true {
            pendingClick?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pendingClick = nil
                self?.controller?.handleLeftClick()
            }
            pendingClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
            return
        }
        controller?.handleLeftClick()
    }

    private func handle(at point: NSPoint) -> ResizeHandle? {
        guard let controller, controller.isResizing else { return nil }
        return PetSizing.handle(at: point, petSize: controller.currentPetSize)
    }

    private func isCharacterPixel(at point: NSPoint) -> Bool {
        guard let cgImage = PetAsset.displayedCGImage(
            state: controller?.displayedPetState ?? .rest,
            isEditingGlints: controller?.isEditingGlints == true
        ) else {
            return true
        }

        let padding: CGFloat = controller?.isResizing == true ? PetSizing.chromePadding : 0
        let petSize = controller?.currentPetSize ?? bounds.width
        let petBounds = NSRect(x: padding, y: padding, width: petSize, height: petSize)
        let fitted = PetMotion.aspectFit(
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            in: petBounds
        )
        guard fitted.contains(point) else { return false }

        let x = (point.x - fitted.minX) / fitted.width * CGFloat(cgImage.width)
        let yFromBottom = (point.y - fitted.minY) / fitted.height * CGFloat(cgImage.height)
        let y = CGFloat(cgImage.height) - yFromBottom
        let pixelX = min(max(Int(x), 0), cgImage.width - 1)
        let pixelY = min(max(Int(y), 0), cgImage.height - 1)

        guard let data = cgImage.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else {
            return true
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let offset = pixelY * cgImage.bytesPerRow + pixelX * bytesPerPixel
        guard bytesPerPixel >= 4 else { return true }
        return pointer[offset + 3] > 16
    }
}

final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
