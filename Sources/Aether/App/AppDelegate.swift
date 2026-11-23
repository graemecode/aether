import AetherCore
import AppKit
import Combine
import SwiftUI

private let wakeupNotificationName = Notification.Name("com.strangechances.Aether.wakeup")

/// Borderless, notch-safe floating panel replacing NSPopover so Aether never clips
/// behind a MacBook camera notch and responds crisply to keyboard shortcuts.
final class AetherFloatingPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?
    var onKeyAction: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        // Don't hijack typing when a SecureField / NSTextView is first responder
        if let first = firstResponder, first is NSTextView {
            if event.keyCode == 53 {
                onEscape?()
                return
            }
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // Escape
            onEscape?()
            return
        }
        if event.keyCode == 49 { // Space -> run networkQuality responsiveness test
            onSpace?()
            return
        }
        if let handled = onKeyAction?(event), handled {
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menuBarIconView: MenuBarIconView!
    private var floatingPanel: AetherFloatingPanel!
    private var hostingController: NSHostingController<PopoverView>!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private let studio = StudioWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DocSnapshotRenderer.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        #endif

        // Single-instance guard
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                DistributedNotificationCenter.default().postNotificationName(
                    wakeupNotificationName,
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                others.first?.activate()
                NSApp.terminate(nil)
                return
            }
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalWakeup),
            name: wakeupNotificationName,
            object: nil
        )

        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        setupMainMenu()
        setupMenuBar()
        setupFloatingPanel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let state = AppState.shared
        state.onMenuBarTick = { [weak self] wifi, audit, throughput, mode, isWired in
            guard let self else { return }
            let widthChanged = self.menuBarIconView.update(
                wifi: wifi,
                audit: audit,
                throughput: throughput,
                mode: mode,
                isWired: isWired
            )
            if widthChanged {
                self.statusItem.length = self.menuBarIconView.preferredWidth
            }
            if let btn = self.statusItem.button {
                btn.toolTip = "Aether — \(state.heroTitle) · \(state.trustPillLabel) · ⌥-Click to copy Local IP · Right-click for menu"
                btn.setAccessibilityTitle("Aether \(state.heroTitle)")
                btn.setAccessibilityValue("\(HumanSummary.humanSignalLabel(wifi: wifi, isWired: isWired)), \(state.trustPillLabel), download \(ByteRateFormatter.detailed(throughput.downloadBytesPerSec)), upload \(ByteRateFormatter.detailed(throughput.uploadBytesPerSec))")
            }
        }

        state.onRequestPanelResize = { [weak self] in
            guard let self, self.floatingPanel.isVisible else { return }
            DispatchQueue.main.async { self.repositionFloatingPanel() }
        }

        // Smoothly re-anchor panel height whenever visible content size can change
        let resizeSignals: [AnyPublisher<Void, Never>] = [
            state.$activeTab.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$stageMode.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$statusBanner.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$qualityResult.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$aiDiagnosis.map { $0 != nil }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$isGeneratingBrief.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$activeInterfaces.map(\.count).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$nearbyNetworks.map(\.count).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$vpns.map(\.count).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$trustAudit.map(\.checks.count).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$hasLocationAccess.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$publicIP.map { $0 != nil }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$qrSharePayload.map { $0 != nil }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$captivePortal.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$isProMode.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$hasDismissedOnboarding.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$wifi.map(\.isConnected).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$wifi.map(\.powerOn).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$knownSSIDs.map(\.count).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$rawScanBSSIDs.map(\.count).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$connectionError.map { $0 != nil }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$connectingSSID.map { $0 != nil }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            state.$didAttemptLocationPrompt.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(resizeSignals)
            .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.floatingPanel.isVisible else { return }
                self.repositionFloatingPanel()
            }
            .store(in: &cancellables)

        state.boot()

        // Open popover automatically only on first launch; Launch-at-Login & subsequent starts stay quiet in menu bar
        if state.consumeShouldAutoOpenOnLaunch() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeDismissMonitors()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        AppState.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app must NEVER quit when Studio or any auxiliary window closes
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    @objc private func handleExternalWakeup() {
        showPopover()
    }

    @objc private func handleScreenParametersChanged() {
        if floatingPanel.isVisible {
            repositionFloatingPanel()
        }
    }

    @objc private func handleAppResignActive() {
        // Close popover when user switches apps so live canvas pauses & idle CPU stays near 0%.
        // Keep open during macOS TCC Location, Touch ID Keychain, or DNS admin sheets.
        guard floatingPanel.isVisible,
              !AppState.shared.isLoadingQR,
              !AppState.shared.isApplyingDNS,
              !AppState.shared.isRequestingLocation else { return }
        closePopover()
    }

    @objc private func handleSystemWake() {
        AppState.shared.handleSystemWake()
    }

    // MARK: - Native macOS Main Menu (enables ⌘W, ⌘Q, ⌘C/⌘V in password fields)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Aether", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        let privacyItem = NSMenuItem(title: "Privacy Policy…", action: #selector(menuPrivacyPolicy), keyEquivalent: "")
        privacyItem.target = self
        appMenu.addItem(privacyItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Aether", action: #selector(menuQuit), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar & Floating Panel

    private func setupMenuBar() {
        let initialWidth = MenuBarIconView.width(for: AppState.shared.menuBarMode)
        statusItem = NSStatusBar.system.statusItem(withLength: initialWidth)
        statusItem.autosaveName = "AetherStatusItem"
        guard let button = statusItem.button else { return }

        menuBarIconView = MenuBarIconView(frame: button.bounds)
        menuBarIconView.autoresizingMask = [.width, .height]
        button.addSubview(menuBarIconView)
        button.target = self
        button.action = #selector(handleStatusBarClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Aether — Signal, Speed & Shield"
    }

    private func setupFloatingPanel() {
        let rootView = PopoverView(
            state: AppState.shared,
            onOpenStudio: { [weak self] in self?.openStudio() },
            onQuit: { NSApp.terminate(nil) },
            onRequestResize: { [weak self] in
                guard let self, self.floatingPanel.isVisible else { return }
                self.repositionFloatingPanel()
            }
        )

        let hc = NSHostingController(rootView: rootView)
        hc.sizingOptions = [.preferredContentSize]
        self.hostingController = hc

        let panel = AetherFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 396, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = hc
        panel.onEscape = { [weak self] in self?.closePopover() }
        panel.onSpace = { AppState.shared.runQualityTest() }
        panel.onKeyAction = { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if mods == .command {
                if chars == "q" { NSApp.terminate(nil); return true }
                if chars == "e" { self?.openStudio(); return true }
                if chars == "p" { AppState.shared.isProMode.toggle(); AppState.shared.performHaptic(); return true }
                if chars == "1" { AppState.shared.selectTab(.speed); return true }
                if chars == "2" { AppState.shared.selectTab(.shield); return true }
                if chars == "3" { AppState.shared.selectTab(.networks); return true }
                if chars == "4" { AppState.shared.selectTab(.tools); return true }
            }
            if mods.isEmpty {
                switch chars {
                case "1": AppState.shared.stageMode = .flux; AppState.shared.performHaptic(); return true
                case "2": AppState.shared.stageMode = .spectrum; AppState.shared.performHaptic(); return true
                case "3": AppState.shared.stageMode = .route; AppState.shared.performHaptic(); return true
                case "r":
                    Task { await AppState.shared.scanNearbyNetworks(force: true) }
                    AppState.shared.performHaptic()
                    return true
                default: break
                }
            }
            return false
        }
        self.floatingPanel = panel
    }

    // MARK: - Actions

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else if event.modifierFlags.contains(.option) {
            if let ip = AppState.shared.route.localIP {
                AppState.shared.copyToClipboard(ip, label: "Local IP")
            }
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if floatingPanel.isVisible {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        AppState.shared.isPopoverOpen = true
        repositionFloatingPanel()
        let finalFrame = floatingPanel.frame
        var startFrame = finalFrame
        startFrame.origin.y += 5
        floatingPanel.alphaValue = 0.0
        floatingPanel.setFrame(startFrame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        floatingPanel.orderFrontRegardless()
        floatingPanel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            floatingPanel.animator().alphaValue = 1.0
            floatingPanel.animator().setFrame(finalFrame, display: true)
        }
        installDismissMonitors()
    }

    private func repositionFloatingPanel() {
        hostingController.view.layoutSubtreeIfNeeded()
        let fitting = hostingController.view.fittingSize
        let btnWindow = statusItem.button?.window
        let screen = btnWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        // Strictly lock width to 396pt so long process names or labels can never widen or jitter the popover
        let maxAllowedHeight = max(360, screen.visibleFrame.height - 24)
        let size = CGSize(
            width: 396,
            height: min(maxAllowedHeight, max(210, ceil(fitting.height)))
        )

        let btnRect: CGRect?
        if let btn = statusItem.button, let win = btn.window {
            let inWin = btn.convert(btn.bounds, to: nil)
            btnRect = win.convertToScreen(inWin)
        } else {
            btnRect = nil
        }

        let placement = MenuBarPositioner.computePlacement(
            buttonScreenRect: btnRect,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea,
            panelSize: size
        )

        if AppState.shared.isStatusItemBehindNotch != placement.statusItemOccludedByNotch {
            AppState.shared.isStatusItemBehindNotch = placement.statusItemOccludedByNotch
        }

        floatingPanel.setFrame(NSRect(origin: placement.origin, size: size), display: true, animate: false)
    }

    private func closePopover() {
        removeDismissMonitors()
        floatingPanel.orderOut(nil)
        AppState.shared.isPopoverOpen = false
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard !AppState.shared.isRequestingLocation else { return }
                self?.closePopover()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.floatingPanel.isVisible else { return event }
            if let win = event.window, win !== self.floatingPanel, win !== self.statusItem.button?.window {
                self.closePopover()
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let g = globalMouseMonitor {
            NSEvent.removeMonitor(g)
            globalMouseMonitor = nil
        }
        if let l = localMouseMonitor {
            NSEvent.removeMonitor(l)
            localMouseMonitor = nil
        }
    }

    // MARK: - Right-Click Quick Menu

    private func showContextMenu() {
        closePopover()
        let menu = NSMenu()
        let state = AppState.shared

        let header = NSMenuItem(title: "\(state.heroTitle) · \(state.trustAudit.level.label)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let studioItem = NSMenuItem(title: "Open Aether Studio (⌘E)", action: #selector(menuOpenStudio), keyEquivalent: "")
        studioItem.target = self
        menu.addItem(studioItem)

        let speedItem = NSMenuItem(title: "Run Speed & Responsiveness Test", action: #selector(menuRunSpeedTest), keyEquivalent: "")
        speedItem.target = self
        menu.addItem(speedItem)

        if let ip = state.route.localIP {
            let copyIP = NSMenuItem(title: "Copy Local IP (\(ip))", action: #selector(menuCopyLocalIP), keyEquivalent: "")
            copyIP.target = self
            menu.addItem(copyIP)
        }

        if !state.isSandboxed {
            let flushItem = NSMenuItem(title: "Flush DNS Cache", action: #selector(menuFlushDNS), keyEquivalent: "")
            flushItem.target = self
            menu.addItem(flushItem)
        }

        let wifiToggle = NSMenuItem(title: state.wifi.powerOn ? "Turn Wi-Fi Off" : "Turn Wi-Fi On", action: #selector(menuToggleWiFi), keyEquivalent: "")
        wifiToggle.target = self
        menu.addItem(wifiToggle)

        menu.addItem(.separator())

        let hideApple = NSMenuItem(title: "Hide Apple Wi-Fi Icon (Control Center)…", action: #selector(menuHideApple), keyEquivalent: "")
        hideApple.target = self
        menu.addItem(hideApple)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(menuToggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = state.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit Aether", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func openStudio() {
        closePopover()
        studio.show()
    }

    @objc private func menuOpenStudio() { openStudio() }

    @objc private func menuRunSpeedTest() {
        showPopover()
        AppState.shared.selectTab(.speed)
        AppState.shared.runQualityTest()
    }

    @objc private func menuCopyLocalIP() {
        if let ip = AppState.shared.route.localIP {
            AppState.shared.copyToClipboard(ip, label: "Local IP")
        }
    }

    @objc private func menuFlushDNS() { AppState.shared.flushDNS() }
    @objc private func menuToggleWiFi() { AppState.shared.toggleWiFiPower() }
    @objc private func menuHideApple() { AppState.shared.openControlCenterSettings() }
    @objc private func menuPrivacyPolicy() { AppState.shared.openPrivacyPolicy() }
    @objc private func menuToggleLogin() { AppState.shared.toggleLaunchAtLogin() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
