import AppKit
import NotchKit
import SwiftUI

/// The island's geometry and the panel it drives (NotchKit's handle driver): drag by the header, resize from the bottom.
@MainActor @Observable final class IslandModel: NotchHandleDriver {
    var geometry: NotchGeometry
    var isMoving = false
    let isFloating = true
    var glow: NotchGlowState = .off
    /// Hanging from the notch (true) or floating as a card.
    var docked = false
    weak var panel: NSPanel?
    private var sweeps = 0
    private var moveStart: (pointer: CGPoint, origin: CGPoint)?
    private var resizeStart: (pointer: CGPoint, height: Double, top: Double)?

    static let size = CGSize(width: 780, height: 550)

    init(display: NotchDisplay?) {
        var g = NotchGeometry.make(notch: display?.notch, builtInNotchWidth: 0, menuBarHeight: display?.menuBarHeight ?? 24)
        g.isFloating = true
        g.expandedSize = Self.size
        geometry = g
    }

    /// Folded into the notch: a small strip the width of the notch plus room for status on each side.
    var collapsed = false
    var collapsedSize: CGSize { CGSize(width: geometry.notch.width + 170, height: max(32, geometry.notch.height)) }
    var size: CGSize { collapsed ? collapsedSize : geometry.expandedSize }
    var panelSize: CGSize { CGSize(width: size.width + 2 * NotchFloat.margin, height: size.height + 2 * NotchFloat.margin) }
    var minHeight: Double { 420 }
    var maxHeight: Double { Double(panel?.screen?.visibleFrame.height ?? 900) - NotchResize.dockClearance }

    func sweep() { sweeps += 1; glow = .sweep(serial: sweeps) }

    func move(_ input: NotchHandleInput) {
        guard let panel else { return }
        switch input {
        case .began(let p): moveStart = (p, panel.frame.origin)
        case .changed(let p):
            guard let s = moveStart else { return }
            if !isMoving, hypot(p.x - s.pointer.x, p.y - s.pointer.y) < NotchFloat.dragThreshold { return }
            isMoving = true
            panel.setFrameOrigin(CGPoint(x: s.origin.x + p.x - s.pointer.x, y: s.origin.y + p.y - s.pointer.y))
        case .ended: moveStart = nil; isMoving = false
        case .cancel:
            if let s = moveStart { panel.setFrameOrigin(s.origin) }
            moveStart = nil; isMoving = false
        case .reset: placeAtTopCentre()
        case .corner(let corner):
            guard let visible = panel.screen?.visibleFrame else { return }
            let inset = NotchFloat.cornerInset - NotchFloat.margin
            let x = corner == .topLeft || corner == .bottomLeft ? visible.minX + inset : visible.maxX - inset - panel.frame.width
            let y = corner == .bottomLeft || corner == .bottomRight ? visible.minY + inset : visible.maxY - inset - panel.frame.height
            panel.setFrameOrigin(CGPoint(x: x, y: y))
        case .step: break
        }
    }

    func resize(_ input: NotchHandleInput) {
        guard let panel else { return }
        switch input {
        case .began(let p): resizeStart = (p, size.height, panel.frame.maxY)
        case .changed(let p):
            guard let s = resizeStart else { return }
            setHeight(NotchResize.live(proposed: s.height + (s.pointer.y - p.y), min: minHeight, max: maxHeight, reduceMotion: false), top: s.top)
        case .ended, .cancel:
            if let s = resizeStart { setHeight(NotchResize.settled(size.height, min: minHeight, max: maxHeight), top: s.top) }
            resizeStart = nil
        case .reset: setHeight(Self.size.height, top: panel.frame.maxY)
        case .step(let d): setHeight(NotchResize.stepped(size.height, by: d, min: minHeight, max: maxHeight), top: panel.frame.maxY)
        case .corner: break
        }
    }

    private func setHeight(_ height: Double, top: Double) {
        geometry.expandedSize.height = height.rounded()
        guard let panel else { return }
        let s = panelSize
        panel.setFrame(CGRect(x: panel.frame.minX, y: top - s.height, width: s.width, height: s.height), display: true)
    }

    /// Hang the island from the notch: centred, its top edge flush with the top of the screen.
    func dock(animate: Bool = false) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        docked = true
        let s = panelSize
        panel.setFrame(CGRect(x: screen.frame.midX - s.width / 2, y: screen.frame.maxY - s.height + NotchFloat.margin,
                              width: s.width, height: s.height), display: true, animate: animate)
    }

    /// Fold into the notch (always docks).
    func collapse() {
        collapsed = true
        dock()
    }

    /// Open out of the notch to the full island.
    func expand() {
        collapsed = false
        dock()
    }

    /// Set while the user drags the island, so programmatic moves never snap it.
    var userDragged = false

    /// After a drag: snap into the notch when let go near it, otherwise float.
    func settleAfterDrag() {
        guard userDragged, let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let islandTop = panel.frame.maxY - NotchFloat.margin
        if screen.frame.maxY - islandTop < 70 && abs(panel.frame.midX - screen.frame.midX) < 180 { dock() } else { docked = false }
        userDragged = false
    }

    func toggleDock() { if docked { docked = false; placeAtTopCentre() } else { dock() } }

    func placeAtTopCentre() {
        guard let panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let s = panelSize
        panel.setFrame(CGRect(x: visible.midX - s.width / 2, y: visible.maxY - s.height + NotchFloat.margin - 12,
                              width: s.width, height: s.height), display: true)
    }
}

/// A borderless panel that can take the keyboard (the game needs it) and floats above other windows.
final class IslandPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar, so it can hang from the notch.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        isMovableByWindowBackground = false
        isMovable = true
        becomesKeyOnlyIfNeeded = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
