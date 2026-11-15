import AppKit
import SwiftUI

final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var hovered: String?
    var notch = CGSize(width: 0, height: 24)

    // Up to this many sessions get one dot each; more show counts per state.
    let maxDots = 4
    // Strip below the camera housing, so the glow isn't hidden behind the hardware notch.
    let lip: CGFloat = 5
    let expandedWidth: CGFloat = 440
    let headerHeight: CGFloat = 30
    let rowHeight: CGFloat = 52
    // One short line per running subagent, under its parent.
    let subagentHeight: CGFloat = 17
    let planHeight: CGFloat = 300
    // Five rows; the list scrolls past that.
    var maxListHeight: CGFloat { 5 * rowHeight }

    func height(of session: Session) -> CGFloat {
        rowHeight + CGFloat(session.subagents.count) * subagentHeight
    }

    func listHeight(_ sessions: [Session]) -> CGFloat {
        min(maxListHeight, sessions.reduce(0) { $0 + height(of: $1) })
    }

    // Height of the card on show, if any, below the notch.
    func cardHeight(_ store: SessionStore) -> CGFloat? {
        if let a = store.approvals.first {
            return 150 + (a.sessionRules.isEmpty ? 0 : 20) + (a.risk.level == .low ? 0 : 20) + (a.diff.isEmpty ? 0 : CGFloat(a.diff.count) * 15 - 18)
        }
        if store.offerConnect || store.replyTo != nil { return 150 }
        if store.plan != nil { return planHeight }
        return store.catchUp.map { 92 + CGFloat(min($0.items.count, 4)) * 44 }
    }

    func earWidth(_ store: SessionStore) -> CGFloat {
        store.headline != nil || store.sessions.count > maxDots ? 84 : 56
    }

    // Quiet mode: nothing beside the notch until an agent needs you.
    func showsEars(_ store: SessionStore) -> Bool {
        !store.sessions.isEmpty && (!store.quiet || store.headline != nil)
    }

    func size(_ store: SessionStore) -> CGSize {
        if let card = cardHeight(store) { return CGSize(width: expandedWidth, height: notch.height + card) }
        if expanded {
            return CGSize(width: expandedWidth, height: notch.height + headerHeight + 14 + listHeight(store.sorted))
        }
        guard showsEars(store) else { return CGSize(width: notch.width, height: notch.height) }
        return CGSize(width: notch.width + earWidth(store) * 2, height: notch.height + lip)
    }

    var windowSize: CGSize {
        CGSize(width: expandedWidth, height: notch.height + max(planHeight, headerHeight + 14 + maxListHeight))
    }
}

// The window is always expanded-size but click-through, except while hovered or showing an approval.
final class NotchPanel: NSPanel {
    private let store: SessionStore
    private let state = NotchState()
    private var hoverTimer: Timer?
    private var hadCard = false
    private lazy var hotkeys = Hotkeys { [weak self] allow in
        guard let store = self?.store, let approval = store.approvals.first else { return }
        store.answer(approval, allow ? "allow" : "deny")
    }

    init(store: SessionStore) {
        self.store = store
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        contentView = FirstClickHostingView(rootView: NotchView(store: store, state: state))
        place()

        // Polling the pointer needs no permissions, unlike global event monitors.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.checkHover() }
    }

    func place() {
        let screen = NSScreen.screens.first { $0.notchSize != nil } ?? NSScreen.main
        guard let screen else { return }
        // No notch (e.g. an external display): hang a small bar from the middle of the menu bar.
        state.notch = screen.notchSize ?? CGSize(width: 0, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        let size = state.windowSize
        setFrame(
            NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    // Key only while typing a reply; non-activating, so the app you're in stays frontmost.
    override var canBecomeKey: Bool { store.replyTo != nil }

    private func checkHover() {
        if store.replyTo != nil && !isKeyWindow { makeKey() }
        // Done replying: hand the keyboard back to the app you were in.
        if store.replyTo == nil && isKeyWindow { NSWorkspace.shared.frontmostApplication?.activate() }

        let card = state.cardHeight(store) != nil
        let size = state.size(store)
        let hotZone = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
            .insetBy(dx: -6, dy: -6)
        let inside = !store.sessions.isEmpty && hotZone.contains(NSEvent.mouseLocation)
        ignoresMouseEvents = !(inside || card)

        if (inside && !state.expanded) || (card && !hadCard) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        hadCard = card
        hotkeys.enabled = !store.approvals.isEmpty
        if inside != state.expanded { state.expanded = inside }
    }
}

// The panel never becomes key, so without this the first click on a button is swallowed.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}
