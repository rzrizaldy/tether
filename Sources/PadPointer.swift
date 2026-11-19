import AppKit

/// Sidecar hides the Mac's pointer while you use the iPad, so you lose it.
/// This draws the Mac's own pointer (arrow, I-beam, hand…) at its normal size
/// in a click-through window that sits exactly under the real one. Sidecar
/// streams it like any window, so the iPad shows a normal pointer again.
/// It only appears while the pointer is on the iPad's screen.
@MainActor
final class PadPointer {
    /// The iPad's screen, in Cocoa coordinates. Nil hides the pointer.
    var screenFrame: NSRect?

    private var window: NSPanel?
    private var imageView: NSImageView?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var hotSpot = NSPoint.zero
    private var shapeKey = ""
    private var lastPoint = NSPoint(x: -1, y: -1)

    var isOn: Bool { window != nil }

    func show() {
        guard window == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let view = NSImageView(frame: panel.contentLayoutRect)
        view.imageScaling = .scaleAxesIndependently
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        window = panel
        imageView = view

        updateShape(force: true)
        follow()
        // Move on every mouse event, at the mouse's own rate, so the drawn
        // pointer doesn't trail the real one. The timer only catches up on the
        // shape and on moves no event reports (a tap on the iPad, say).
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.follow() }
            return event
        }) { monitors.append(l) }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateShape(force: false); self?.follow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        imageView = nil
    }

    private func follow() {
        guard let window else { return }
        let p = NSEvent.mouseLocation
        guard let frame = screenFrame, frame.contains(p) else {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        if p == lastPoint, window.isVisible { return }
        lastPoint = p
        let size = window.frame.size
        // Cursor images are drawn from the top-left; Cocoa windows from the bottom-left.
        window.setFrameOrigin(NSPoint(x: p.x - hotSpot.x, y: p.y - (size.height - hotSpot.y)))
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private func updateShape(force: Bool) {
        guard let cursor = NSCursor.currentSystem ?? Optional(NSCursor.arrow) else { return }
        let image = cursor.image
        let key = "\(image.size.width)x\(image.size.height)@\(cursor.hotSpot.x),\(cursor.hotSpot.y)"
        guard force || key != shapeKey else { return }
        shapeKey = key
        lastPoint = NSPoint(x: -1, y: -1)   // the hot spot moved: place it again
        let scale = CGFloat(max(1, Cursor.scale ?? 1))
        hotSpot = NSPoint(x: cursor.hotSpot.x * scale, y: cursor.hotSpot.y * scale)
        imageView?.image = image
        window?.setContentSize(NSSize(width: image.size.width * scale, height: image.size.height * scale))
    }
}
