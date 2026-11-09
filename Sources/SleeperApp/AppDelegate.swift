import AppKit
import Carbon.HIToolbox
import NotchKit
import SwiftUI

/// The app: a menu bar item, a global hot key (⌃⌥S) and the floating island.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: IslandPanel?
    private var island: IslandModel?
    let controller = GameController()
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private struct Drag { var pointer: CGPoint; var origin: CGPoint; var wasDocked: Bool; var moving = false }
    private var drag: Drag?
    private var hotKey: HotKey?
    var snapshotDir: URL?
    var selfTest = false
    private var tester: SelfTest?
    private var activity: NSObjectProtocol?
    private var script: SnapshotScript?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let displays = NotchScreens.displays()
        let island = IslandModel(display: displays.first { $0.isBuiltIn } ?? displays.first)
        let panel = IslandPanel(size: island.panelSize)
        let host = NSHostingView(rootView: IslandView(island: island, controller: controller))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let container = NSView(frame: CGRect(origin: .zero, size: island.panelSize))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container
        island.panel = panel
        island.dock()
        self.panel = panel
        self.island = island

        setUpStatusItem()
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey)) { [weak self] in self?.toggle() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self, let panel = self.panel, panel.isKeyWindow else { return e }
            return self.handleKey(e) ? nil : e
        }
        // Drag the island by its header band with the system window drag (reliable on a borderless panel, first click
        // included). Double-click the band to send it back to the top centre.
        // Drag the island by its header band. We move the window ourselves (the system drag keeps windows out of
        // the menu bar), and when it's let go near the top centre it docks into the notch.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in
            guard let self, let panel = self.panel, let island = self.island, e.window === panel else { return e }
            switch e.type {
            case .leftMouseDown:
                if island.collapsed { self.show(); return nil }
                let p = e.locationInWindow
                let m = NotchFloat.margin
                let band = max(32, island.geometry.notch.height)
                let top = panel.frame.height - m
                guard p.x >= m, p.x <= panel.frame.width - m, p.y <= top, p.y >= top - band else { return e }
                if e.clickCount == 2 { island.toggleDock(); return nil }
                panel.makeKey()
                self.drag = Drag(pointer: NSEvent.mouseLocation, origin: panel.frame.origin, wasDocked: island.docked)
                return nil
            case .leftMouseDragged:
                guard var d = self.drag else { return e }
                let now = NSEvent.mouseLocation
                let dx = now.x - d.pointer.x, dy = now.y - d.pointer.y
                if !d.moving, hypot(dx, dy) < 4 { return nil }
                if !d.moving { d.moving = true; island.docked = false; self.drag = d }
                panel.setFrameOrigin(CGPoint(x: d.origin.x + dx, y: d.origin.y + dy))
                island.dockPreview = island.nearNotch()
                return nil
            case .leftMouseUp:
                guard let d = self.drag else { return e }
                self.drag = nil
                island.dockPreview = false
                if d.moving { island.settle() } else { island.docked = d.wasDocked }
                return nil
            default:
                return e
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.controller.snapshotMode else { return }
                self.controller.releaseAllKeys(); self.controller.paused = true
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.paused = false }
        }
        show()
        if ProcessInfo.processInfo.environment["SLEEPER_DOCK_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let sc = panel.screen ?? NSScreen.main!
                print("screen", sc.frame, "visible", sc.visibleFrame, "safeTop", sc.safeAreaInsets.top)
                print("notch", island.geometry.notch, "panel", panel.frame, "islandTop", panel.frame.maxY - NotchFloat.margin)
                // A drag that ends just below the menu bar, a little off centre: should dock.
                island.docked = false
                panel.setFrameOrigin(CGPoint(x: panel.frame.origin.x + 60, y: panel.frame.origin.y - 70))
                print("near notch?", island.nearNotch())
                island.settle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    print("after settle near: docked", island.docked, "panel", panel.frame, "islandTop", panel.frame.maxY - NotchFloat.margin)
                    // A drag that ends in the middle of the screen: should float there.
                    panel.setFrameOrigin(CGPoint(x: 300, y: 300))
                    island.docked = false
                    island.settle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        print("after settle far: docked", island.docked, "panel", panel.frame)
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        if selfTest {
            controller.snapshotMode = true
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Self-test")
            let t = SelfTest(controller: controller)
            tester = t
            t.run()
        }
        if let snapshotDir {
            controller.snapshotMode = true
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Snapshots")
            let s = SnapshotScript(dir: snapshotDir, panel: panel, controller: controller)
            script = s
            s.run()
        }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) { return false }  // ⌘Q and friends
        let down = e.type == .keyDown
        if e.keyCode == 53 {  // Esc
            guard down else { return true }
            if controller.chatOpen { controller.closeChat() }
            else if controller.miniGame != nil { controller.closeMiniGame() }
            else if controller.showMap { controller.showMap = false }
            else { fold() }
            return true
        }
        return controller.key(down: down, code: e.keyCode, repeat: e.isARepeat)
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "bubbles.and.sparkles.fill", accessibilityDescription: "Sleeper")
        let menu = NSMenu()
        let play = NSMenuItem(title: "Play Sleeper", action: #selector(menuShow), keyEquivalent: "s")
        play.keyEquivalentModifierMask = [.control, .option]
        play.target = self
        menu.addItem(play)
        let attach = NSMenuItem(title: "Attach to Notch", action: #selector(menuAttach), keyEquivalent: "")
        attach.target = self
        menu.addItem(attach)
        let recentre = NSMenuItem(title: "Float at Top Centre", action: #selector(menuRecentre), keyEquivalent: "")
        recentre.target = self
        menu.addItem(recentre)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Sleeper", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func menuShow() { show() }
    @objc private func menuRecentre() { island?.docked = false; island?.placeAtTopCentre() }
    @objc private func menuAttach() { island?.dock() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    func toggle() { if island?.collapsed == false && panel?.isKeyWindow == true { fold() } else { show() } }

    /// Open the island (out of the notch if it was folded) and take the keyboard.
    func show() {
        guard let panel, let island else { return }
        if island.collapsed { island.expand() }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        controller.paused = false
        island.sweep()
    }

    /// Fold into the notch: the game pauses and the keyboard goes back to the app you were using.
    func fold() {
        controller.releaseAllKeys()
        controller.paused = true
        controller.closeMiniGame()
        island?.collapse()
        panel?.resignKey()
        NSApp.deactivate()
        panel?.orderFrontRegardless()
    }
}

/// A global hot key through Carbon: the app hears only this combination and needs no Accessibility access.
final class HotKey: @unchecked Sendable {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return noErr }
            let hk = Unmanaged<HotKey>.fromOpaque(data).takeUnretainedValue()
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { hk.action() }
            return noErr
        }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x534C_5052), id: 1)  // "SLPR"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
