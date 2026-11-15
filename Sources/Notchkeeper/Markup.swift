import AppKit

// Freezes the screen under the pointer so you can draw on it, then saves screenshot plus drawing as a PNG.
final class Markup: NSWindow {
    private static var current: Markup?
    private let canvas: MarkupCanvas
    private let done: (URL) -> Void

    static func start(done: @escaping (URL) -> Void) {
        guard current == nil else { return }
        // Without Screen Recording, screencapture returns only the wallpaper.
        guard CGPreflightScreenCaptureAccess() else { CGRequestScreenCaptureAccess(); return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let primary = NSScreen.screens.first else { return }
        let f = screen.frame
        let rect = "\(Int(f.minX)),\(Int(primary.frame.maxY - f.maxY)),\(Int(f.width)),\(Int(f.height))"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notchkeeper-markup.png")
        DispatchQueue.global().async {
            _ = ClaudeCLI.run("/usr/sbin/screencapture", ["-x", "-R", rect, file.path])
            let shot = NSImage(contentsOf: file)
            try? FileManager.default.removeItem(at: file)
            DispatchQueue.main.async {
                guard let shot else { return }
                current = Markup(screen: screen, shot: shot, done: done)
            }
        }
    }

    private init(screen: NSScreen, shot: NSImage, done: @escaping (URL) -> Void) {
        canvas = MarkupCanvas(shot: shot)
        self.done = done
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = canvas
        canvas.onFinish = { [weak self] in self?.finish($0) }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(canvas)
        NSCursor.crosshair.push()
    }

    override var canBecomeKey: Bool { true }

    private func finish(_ save: Bool) {
        NSCursor.pop()
        let png = save ? canvas.render() : nil
        orderOut(nil)
        Self.current = nil
        guard let png else { return }
        let url = SessionStore.pasteDir.appendingPathComponent(UUID().uuidString + ".png")
        try? FileManager.default.createDirectory(at: SessionStore.pasteDir, withIntermediateDirectories: true)
        if (try? png.write(to: url)) != nil { done(url) }
    }
}

final class MarkupCanvas: NSView {
    private let shot: NSImage
    private var strokes: [NSBezierPath] = []
    private let hint = NSTextField(labelWithString: "Draw on what you mean   ↩ ask   ⌘Z undo   esc cancel")
    var onFinish: ((Bool) -> Void)?

    init(shot: NSImage) {
        self.shot = shot
        super.init(frame: .zero)
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textColor = .white
        hint.alignment = .center
        hint.wantsLayer = true
        hint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        hint.layer?.cornerRadius = 8
        addSubview(hint)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let size = NSSize(width: hint.intrinsicContentSize.width + 28, height: 30)
        hint.frame = NSRect(x: bounds.midX - size.width / 2, y: bounds.maxY - 80, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        shot.draw(in: bounds)
        NSColor.systemRed.setStroke()
        strokes.forEach { $0.stroke() }
    }

    override func mouseDown(with event: NSEvent) {
        let path = NSBezierPath()
        path.lineWidth = 5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: convert(event.locationInWindow, from: nil))
        strokes.append(path)
    }

    override func mouseDragged(with event: NSEvent) {
        strokes.last?.line(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onFinish?(true)
        case 53: onFinish?(false)
        case 6 where event.modifierFlags.contains(.command):
            _ = strokes.popLast()
            needsDisplay = true
        default: super.keyDown(with: event)
        }
    }

    func render() -> Data? {
        hint.isHidden = true
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
