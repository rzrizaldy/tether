import AppKit
import CoreGraphics

/// Lid-closed support. macOS sleeps on lid close unless a "real" external
/// display is attached, and Sidecar doesn't count. `pmset disablesleep`
/// overrides that, but needs root — so a one-time sudoers rule lets this app
/// flip exactly that one setting, nothing else.
enum Power {
    static let rulePath = "/etc/sudoers.d/tether"
    static var isSetUp: Bool { FileManager.default.fileExists(atPath: rulePath) }

    @discardableResult
    static func keepAwakeWithLidClosed(_ on: Bool) -> Bool {
        guard isSetUp else { return false }
        return run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]) == 0
    }

    static func install() -> Bool {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return false }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
        let tmp = NSTemporaryDirectory() + "tether.sudoers"
        guard (try? rule.write(toFile: tmp, atomically: true, encoding: .utf8)) != nil else { return false }
        let sh = "/usr/sbin/visudo -cf '\(tmp)' && /usr/bin/install -m 0440 -o root -g wheel '\(tmp)' \(rulePath); rm -f '\(tmp)'"
        let script = """
        do shell script "\(sh)" with prompt "Tether needs your password once so the Mac can stay awake with the lid closed while your iPad is the screen." with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil && isSetUp
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

/// Moves the menu bar + Dock onto the iPad so nothing lands on the broken panel.
enum Displays {
    static func sidecarDisplay(named name: String) -> CGDirectDisplayID? {
        for screen in NSScreen.screens {
            let n = screen.localizedName
            guard n == name || n.localizedCaseInsensitiveContains("iPad") || n.localizedCaseInsensitiveContains("Sidecar"),
                  let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  CGDisplayIsBuiltin(id) == 0
            else { continue }
            return id
        }
        return nil
    }

    /// The main display is whichever one sits at origin (0,0).
    @discardableResult
    static func makeMain(_ target: CGDirectDisplayID) -> Bool {
        let shift = CGDisplayBounds(target).origin
        if shift == .zero { return true }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        for id in ids.prefix(Int(count)) where CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay {
            let o = CGDisplayBounds(id).origin
            CGConfigureDisplayOrigin(config, id, Int32(o.x - shift.x), Int32(o.y - shift.y))
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
