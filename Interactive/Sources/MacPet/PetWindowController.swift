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
    private var keyboardMonitor: KeyboardActivityMonitor?
    private var typingReturnID: String?
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
        PetExpressions.restoreSelection()
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
        observeEnergySignals()
        keyboardMonitor = KeyboardActivityMonitor { [weak self] active in self?.typingChanged(active) }
        if UserDefaults.standard.bool(forKey: "keyboardInteractionEnabled") { keyboardMonitor?.start(prompt: false) }
        updateMotionClock()

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
        updateMotionClock()
    }

    func hidePet() {
        typingChanged(false)
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
        updateMotionClock()
    }

    func handleLeftClick() {
        runtime.handleLeftClick()
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

    func applyPetSize(_ size: CGFloat) {
        let footprint = petFootprint()
        runtime.petSize = size
        layoutWindow(footMidX: footprint.midX, footMinY: footprint.minY)
        schedulePersist()
    }

    func makeContextMenu() -> NSMenu {
        typingChanged(false)
        let menu = NSMenu()
        let typingMenu = NSMenu()
        let typingItem = menu.addItem(withTitle: "键盘互动", action: nil, keyEquivalent: "")
        typingItem.submenu = typingMenu
        let status = typingMenu.addItem(withTitle: keyboardMonitor?.isListening == true ? "状态：正在监听按键活动" : (UserDefaults.standard.bool(forKey: "keyboardInteractionEnabled") ? "状态：等待输入监控权限，授权后自动重连" : "状态：已关闭"), action: nil, keyEquivalent: "")
        status.isEnabled = false
        let enabled = typingMenu.addItem(withTitle: "启用打字联动", action: #selector(toggleTyping), keyEquivalent: "")
        enabled.target = self
        enabled.state = UserDefaults.standard.bool(forKey: "keyboardInteractionEnabled") ? .on : .off
        for entry in PetExpressions.entries() {
            let item = typingMenu.addItem(withTitle: entry.name, action: #selector(setTypingExpression(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.state = UserDefaults.standard.string(forKey: "typingExpressionID") == entry.id ? .on : .off
        }

        let expressionItem = menu.addItem(withTitle: "切换表情", action: nil, keyEquivalent: "")
        let expressions = NSMenu()
        for entry in PetExpressions.entries() {
            let item = expressions.addItem(withTitle: entry.name, action: #selector(selectExpression(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.state = entry.id == PetExpressions.selectedID ? .on : .off
            item.view = ExpressionMenuRow(
                title: entry.name,
                selected: entry.id == PetExpressions.selectedID,
                canRemove: entry.id != PetExpressions.legacyID,
                onSelect: { [weak self, weak expressions] in
                    expressions?.cancelTracking()
                    let selection = NSMenuItem()
                    selection.representedObject = entry.id
                    self?.selectExpression(selection)
                },
                onRemove: { [weak self, weak expressions] in
                    expressions?.cancelTracking()
                    // Leave menu tracking before changing files and the selected pet.
                    DispatchQueue.main.async { [weak self] in
                        do {
                            try PetExpressions.remove(entry)
                            self?.applyLoadedCharacter()
                            self?.updateMotionClock()
                            self?.showBanner("已移除「\(entry.name)」")
                        } catch { self?.showExpressionError(error) }
                    }
                }
            )
        }
        expressions.addItem(.separator())
        let importItem = expressions.addItem(withTitle: "导入表情…", action: #selector(importExpressions), keyEquivalent: "")
        importItem.target = self
        let batchItem = expressions.addItem(withTitle: "批量删除…", action: #selector(batchDeleteExpressions), keyEquivalent: "")
        batchItem.target = self
        batchItem.isEnabled = PetExpressions.entries().contains { $0.id != PetExpressions.legacyID }
        expressionItem.submenu = expressions
        let speedItem = menu.addItem(withTitle: "动画速度", action: nil, keyEquivalent: "")
        let speeds = NSMenu()
        for (title, speed) in PetExpressions.playbackSpeeds {
            let item = speeds.addItem(withTitle: title, action: #selector(changeAnimationSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: speed)
            item.state = speed == PetExpressions.playbackSpeed ? .on : .off
        }
        speedItem.submenu = speeds
        let energyItem = menu.addItem(withTitle: "省电模式（推荐）", action: #selector(toggleEnergySaving), keyEquivalent: "")
        energyItem.target = self
        energyItem.state = PetExpressions.energySaving ? .on : .off
        menu.addItem(.separator())
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
        glintItem.isEnabled = !PetExpressions.isActive
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

    @objc private func toggleTyping() {
        let defaults = UserDefaults.standard
        let enable = !defaults.bool(forKey: "keyboardInteractionEnabled")
        if enable {
            if defaults.string(forKey: "typingExpressionID") == nil {
                defaults.set(PetExpressions.selectedID, forKey: "typingExpressionID")
            }
            defaults.set(true, forKey: "keyboardInteractionEnabled")
            if keyboardMonitor?.start(prompt: true) != true {
                let alert = NSAlert()
                alert.messageText = "请允许输入监控"
                alert.informativeText = "在系统设置 → 隐私与安全性 → 输入监控中允许 MacPet 互动版，授权后会自动重连；如果系统要求，请退出后重新打开互动版。仅检测按键活动，不读取、保存或发送输入内容。"
                alert.runModal()
                return
            }
        } else { keyboardMonitor?.stop(); typingChanged(false) }
        defaults.set(enable, forKey: "keyboardInteractionEnabled")
    }

    @objc private func setTypingExpression(_ sender: NSMenuItem) {
        typingChanged(false)
        UserDefaults.standard.set(sender.representedObject as? String, forKey: "typingExpressionID")
    }

    private func typingChanged(_ active: Bool) {
        if active {
            guard typingReturnID == nil, window?.isVisible == true,
                  !isScreenLocked, !isDisplayAsleep,
                  let id = UserDefaults.standard.string(forKey: "typingExpressionID"),
                  id != PetExpressions.selectedID,
                  let entry = PetExpressions.entries().first(where: { $0.id == id }) else { return }
            let original = PetExpressions.selectedID
            do { try PetExpressions.select(entry, persist: false); typingReturnID = original }
            catch { return }
        } else {
            guard let original = typingReturnID else { return }
            typingReturnID = nil
            let entries = PetExpressions.entries()
            if let entry = entries.first(where: { $0.id == original }) ?? entries.first {
                try? PetExpressions.select(entry, persist: false)
            }
        }
        applyLoadedCharacter()
        updateMotionClock()
    }

    @objc private func selectExpression(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = PetExpressions.entries().first(where: { $0.id == id }) else { return }
        do {
            try PetExpressions.select(entry)
            applyLoadedCharacter()
            updateMotionClock()
        } catch { showExpressionError(error) }
    }

    @objc private func toggleEnergySaving() {
        PetExpressions.energySaving.toggle()
        updateMotionClock()
        showBanner(PetExpressions.energySaving ? "已开启省电模式" : "已关闭省电模式")
    }

    @objc private func changeAnimationSpeed(_ sender: NSMenuItem) {
        guard let speed = sender.representedObject as? NSNumber else { return }
        PetExpressions.setPlaybackSpeed(speed.doubleValue)
        refreshPresentation()
        showBanner("动画速度 \(speed.doubleValue)×")
    }

    @objc private func batchDeleteExpressions() {
        let entries = PetExpressions.entries().filter { $0.id != PetExpressions.legacyID }
        guard !entries.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        let picker = ExpressionDeletionPicker(entries: entries)
        let alert = NSAlert()
        alert.messageText = "批量删除表情"
        alert.informativeText = "勾选要删除的表情。导入的副本移入废纸篓，原始文件不受影响。"
        alert.accessoryView = picker
        let delete = alert.addButton(withTitle: "删除所选")
        delete.isEnabled = false
        delete.keyEquivalent = ""
        picker.deleteButton = delete
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selected = picker.selectedEntries
        let failures = PetExpressions.remove(selected)
        applyLoadedCharacter()
        updateMotionClock()
        showBanner("已删除 \(selected.count - failures.count) 个表情")
        if !failures.isEmpty {
            let failure = NSAlert()
            failure.messageText = "部分表情未能删除"
            failure.informativeText = failures.joined(separator: "、")
            failure.runModal()
        }
    }

    @objc private func importExpressions() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "导入表情"
        panel.message = "选择 GIF 动画或 PNG，文件名会作为表情名称，可一次选择多个"
        panel.allowedContentTypes = [.gif, .png]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        var failures: [String] = []
        for url in panel.urls {
            do {
                let entry = try PetExpressions.importExpression(from: url)
                try PetExpressions.select(entry)
            } catch { failures.append(url.lastPathComponent) }
        }
        applyLoadedCharacter()
        updateMotionClock()
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "部分表情未能导入"
            alert.informativeText = failures.joined(separator: "、") + "\n请使用有效的 GIF 或 PNG；解码后的总大小须小于 256 MB。"
            alert.runModal()
        }
    }

    private func showExpressionError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "无法加载表情"
        alert.informativeText = error.localizedDescription
        alert.runModal()
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
            refreshPresentation()
        }
    }

    @objc private func resetGlints() {
        runtime.resetGlints()
        refreshPresentation()
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
        try? PetExpressions.select(PetExpressions.entries()[0])
        applyLoadedCharacter()
    }

    @objc private func restoreDefaultCharacter() {
        try? PetExpressions.select(PetExpressions.entries()[0])
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
        refreshPresentation()
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
        refreshPresentation()
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
        refreshPresentation()
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
            $0.refreshPresentation()
        }
        observeEnergy(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) {
            $0.updateMotionClock()
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

    private var canDriveFrames: Bool {
        PetEnergy.shouldDriveFrames(
            isWindowOnscreen: window?.isVisible == true,
            isWindowOccluded: isWindowOccluded,
            isDisplayAsleep: isDisplayAsleep,
            isScreenLocked: isScreenLocked,
            isPoseFrozen: isEditingGlints
        )
    }

    private func updateMotionClock() {
        stopMotionClock()
        guard canDriveFrames else { return }
        motionTick()
    }

    private func scheduleNextFrame(at date: Date) {
        guard canDriveFrames else { return }
        let fps = PetEnergy.maximumFPS(energySaving: PetExpressions.energySaving,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        let delay: TimeInterval
        if PetExpressions.isActive {
            guard let next = PetExpressions.nextFrameDelay(at: date, maximumFPS: fps) else { return }
            delay = next
        } else {
            delay = 1 / fps
        }
        let timer = Timer(timeInterval: delay, target: self,
            selector: #selector(motionTick), userInfo: nil, repeats: false)
        timer.tolerance = min(delay * 0.15, 0.03)
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
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

    private func refreshPresentation() {
        hostingView.rootView = PetView(
            display: display,
            size: runtime.petSize,
            reduceMotion: reduceMotion,
            isResizing: isResizing,
            isEditingGlints: isEditingGlints,
            leftGlint: runtime.leftGlint,
            rightGlint: runtime.rightGlint
        )
        motionTick()
    }

    @objc private func motionTick() {
        stopMotionClock()
        let date = Date()
        PetExpressions.advance(at: date)
        if display.expressionImage !== PetExpressions.image {
            display.expressionImage = PetExpressions.image
            display.expressionFrame = PetExpressions.frameIndex
        }
        if !PetExpressions.isActive {
            updateLook()
            display.tick = date
        }
        scheduleNextFrame(at: date)
    }

    private func updateLook() {
        if isEditingGlints || PetExpressions.isActive {
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
        ).scaled(by: PetMotion.lookWeight(isResizing: isResizing))
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
        guard event.clickCount == 1 else { return }
        controller?.handleLeftClick()
    }

    private func handle(at point: NSPoint) -> ResizeHandle? {
        guard let controller, controller.isResizing else { return nil }
        return PetSizing.handle(at: point, petSize: controller.currentPetSize)
    }

    private func isCharacterPixel(at point: NSPoint) -> Bool {
        guard let cgImage = PetAsset.characterCGImage() else {
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

