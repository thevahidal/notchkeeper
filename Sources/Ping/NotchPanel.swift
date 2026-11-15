import AppKit
import SwiftUI

final class NotchState: ObservableObject {
    @Published var expanded = false
    var notch = CGSize(width: 0, height: 24)

    // Up to this many sessions get one dot each; more show counts per state.
    let maxDots = 4
    // Strip below the camera housing, so the glow isn't hidden behind the hardware notch.
    let lip: CGFloat = 5
    let expandedWidth: CGFloat = 400
    let rowHeight: CGFloat = 40
    let cardHeight: CGFloat = 150
    // Five rows; the list scrolls past that.
    var maxListHeight: CGFloat { 5 * rowHeight }

    func earWidth(_ count: Int) -> CGFloat { count > maxDots ? 78 : 60 }

    // One short line per running subagent, under its parent.
    let subagentHeight: CGFloat = 17

    func height(of session: Session) -> CGFloat {
        rowHeight + CGFloat(session.subagents.count) * subagentHeight
    }

    func listHeight(_ sessions: [Session]) -> CGFloat {
        min(maxListHeight, sessions.reduce(0) { $0 + height(of: $1) })
    }

    func size(for sessions: [Session], card: Bool) -> CGSize {
        if card { return CGSize(width: expandedWidth, height: notch.height + cardHeight) }
        if expanded { return CGSize(width: expandedWidth, height: notch.height + 16 + listHeight(sessions)) }
        if sessions.isEmpty { return CGSize(width: notch.width, height: notch.height) }
        return CGSize(width: notch.width + earWidth(sessions.count) * 2, height: notch.height + lip)
    }

    var windowSize: CGSize {
        CGSize(width: expandedWidth, height: notch.height + max(cardHeight, 16 + maxListHeight))
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
        state.notch = screen.notchSize ?? CGSize(width: 0, height: 24)
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

        let card = !store.approvals.isEmpty || store.replyTo != nil || store.offerConnect
        let size = state.size(for: store.sorted, card: card)
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
