import AppKit
import QuartzCore

/// Sidecar hides the Mac's pointer while you use the iPad by touch, so you
/// lose track of it. This draws a ring around the pointer in a click-through
/// window. Sidecar streams the whole screen, so the ring shows on the iPad even
/// when the real pointer doesn't.
@MainActor
final class Halo {
    private let size: CGFloat = 46
    private var window: NSPanel?
    private var timer: Timer?
    private var last = NSPoint(x: -1, y: -1)
    private var lastMove = Date()

    var isOn: Bool { window != nil }

    func show() {
        guard window == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let view = NSView(frame: panel.contentLayoutRect)
        view.wantsLayer = true
        let ring = CAShapeLayer()
        let inset: CGFloat = 4
        ring.path = CGPath(ellipseIn: CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset), transform: nil)
        ring.fillColor = NSColor(calibratedRed: 0.35, green: 0.84, blue: 0.63, alpha: 0.18).cgColor
        ring.strokeColor = NSColor(calibratedRed: 0.35, green: 0.84, blue: 0.63, alpha: 0.95).cgColor
        ring.lineWidth = 3
        ring.shadowColor = NSColor.black.cgColor
        ring.shadowOpacity = 0.55
        ring.shadowRadius = 2
        ring.shadowOffset = .zero
        view.layer?.addSublayer(ring)
        panel.contentView = view
        window = panel

        follow()
        panel.orderFrontRegardless()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func follow() {
        guard let window else { return }
        let p = NSEvent.mouseLocation
        if p != last {
            last = p
            lastMove = Date()
            window.setFrameOrigin(NSPoint(x: p.x - size / 2, y: p.y - size / 2))
            window.orderFrontRegardless()
        }
        // Bright while moving, quieter when the pointer sits still.
        let idle = Date().timeIntervalSince(lastMove)
        window.alphaValue = idle < 1.5 ? 1 : max(0.45, 1 - (idle - 1.5) / 2)
    }
}
