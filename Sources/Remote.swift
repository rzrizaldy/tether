import AppKit
import IOKit.ps

/// A software "HDMI dummy": a Retina display shaped like the iPad, so Screen
/// Sharing from far away shows a proper Mac desktop even when the lid is shut
/// and the real screen is broken. It vanishes the moment Tether quits.
@MainActor
final class VirtualScreen {
    private var display: CGVirtualDisplay?
    var displayID: CGDirectDisplayID? { display?.displayID }
    var isOn: Bool { display != nil }

    /// Point sizes at 2x. The first is the iPad Air 11", pixel for pixel;
    /// the others show up as "More Space" in System Settings › Displays.
    private static let modes: [(UInt32, UInt32)] = [(1180, 820), (1366, 950), (1536, 1068), (983, 683)]

    func show() {
        guard display == nil else { return }
        let d = CGVirtualDisplayDescriptor()
        d.queue = .main
        d.name = "Tether Display"
        d.maxPixelsWide = 3072
        d.maxPixelsHigh = 2136
        d.sizeInMillimeters = CGSize(width: 228, height: 158) // an 11-inch iPad
        d.vendorID = 0x7E7E
        d.productID = 0x0001
        d.serialNum = 0x0001
        d.terminationHandler = { _, _ in Log.write("Virtual display ended by the system") }
        guard let v = CGVirtualDisplay(descriptor: d) else { Log.write("Virtual display: could not create"); return }
        let s = CGVirtualDisplaySettings()
        s.hiDPI = 1
        s.modes = Self.modes.map { CGVirtualDisplayMode(width: $0.0 * 2, height: $0.1 * 2, refreshRate: 60) }
        guard v.apply(s) else { Log.write("Virtual display: settings refused"); return }
        display = v
        Log.write("Virtual display on (id \(v.displayID))")
    }

    func hide() {
        guard display != nil else { return }
        display = nil
        Log.write("Virtual display off")
    }
}

/// What Remote mode needs to know about the outside world.
enum Remote {
    static var onCharger: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPSACPowerValue
    }

    /// Screen Sharing listens on 5900 once it's switched on in System Settings.
    static var screenSharingOn: Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(5900).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }

    /// The Mac's Tailscale name, if Tailscale is installed and up.
    static func tailscaleName() -> String? {
        let cli = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        guard FileManager.default.isExecutableFile(atPath: cli) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = ["status", "--self", "--json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let me = json["Self"] as? [String: Any], (me["Online"] as? Bool) ?? false,
              let dns = me["DNSName"] as? String, !dns.isEmpty else { return nil }
        return dns.hasSuffix(".") ? String(dns.dropLast()) : dns
    }

    static func openSharingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
