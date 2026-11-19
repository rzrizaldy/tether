import Foundation
import IOKit
import IOKit.usb

/// Fires when an iPad is plugged into / unplugged from a USB port.
final class USBWatcher {
    var onChange: (() -> Void)?
    private(set) var pads = Set<UInt64>()
    var iPadPlugged: Bool { !pads.isEmpty }

    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0

    func start() {
        port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, Self.appleUSB(), { ctx, it in
            Unmanaged<USBWatcher>.fromOpaque(ctx!).takeUnretainedValue().drain(it, plugged: true)
        }, ctx, &added)
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, Self.appleUSB(), { ctx, it in
            Unmanaged<USBWatcher>.fromOpaque(ctx!).takeUnretainedValue().drain(it, plugged: false)
        }, ctx, &removed)

        // Arm both iterators and pick up an iPad that is already plugged in.
        drain(added, plugged: true)
        drain(removed, plugged: false)
    }

    private static func appleUSB() -> CFDictionary {
        // A bare "idVendor" key matches nothing for IOUSBHostDevice; it has to
        // sit under IOPropertyMatch.
        let match = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        match[kIOPropertyMatchKey] = ["idVendor": 0x05AC]
        return match
    }

    private func drain(_ iterator: io_iterator_t, plugged: Bool) {
        var changed = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            if plugged {
                let name = Self.name(service)
                let pid = (IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int) ?? 0
                let pad = name.localizedCaseInsensitiveContains("iPad")
                Log.write("USB in: \"\(name)\" product=0x\(String(pid, radix: 16)) \(pad ? "→ iPad" : "(not an iPad)")")
                if pad, pads.insert(id).inserted { changed = true }
            } else if pads.remove(id) != nil {
                Log.write("USB out: iPad")
                changed = true
            }
        }
        if changed { onChange?() }
    }

    private static func name(_ service: io_service_t) -> String {
        for key in ["USB Product Name", "kUSBProductString", "Product Name"] {
            if let name = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String {
                return name
            }
        }
        var buf = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(service, &buf)
        return String(cString: buf)
    }
}
