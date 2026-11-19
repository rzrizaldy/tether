import Foundation

/// Thin wrapper over Apple's private SidecarCore framework (the same thing
/// Control Center uses when you pick "Use as separate display").
final class Sidecar {
    private let manager: NSObject?

    init() {
        dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY)
        let cls = NSClassFromString("SidecarDisplayManager") as? NSObject.Type
        manager = cls?.perform(Selector(("sharedManager")))?.takeUnretainedValue() as? NSObject
    }

    var isAvailable: Bool { manager != nil }

    /// iPads Sidecar knows about (signed in to the same Apple ID).
    var devices: [NSObject] { list("devices").filter(Self.isPad) }
    var connected: [NSObject] { list("connectedDevices") }
    var isConnected: Bool { !connected.isEmpty }

    static func name(_ device: NSObject) -> String {
        (device.value(forKey: "name") as? String) ?? "iPad"
    }

    private static func isPad(_ device: NSObject) -> Bool {
        let model = (device.value(forKey: "model") as? String) ?? ""
        return model.isEmpty || model.hasPrefix("iPad")
    }

    /// `wired: true` forces the USB cable (transport 2), the same trick
    /// SidecarLauncher's `-wired` uses. Plain connect lets Sidecar pick, and it
    /// often picks wireless or nothing at all.
    func connect(_ device: NSObject, wired: Bool, done: @escaping (Error?) -> Void) {
        guard wired else { return call("connectToDevice:completion:", device, done) }
        let sel = Selector(("connectToDevice:withConfig:completion:"))
        guard let m = manager, m.responds(to: sel),
              let configClass = NSClassFromString("SidecarDisplayConfig") as? NSObject.Type else {
            return call("connectToDevice:completion:", device, done)
        }
        let config = configClass.init()
        let setTransport = Selector(("setTransport:"))
        if config.responds(to: setTransport) {
            typealias SetFn = @convention(c) (AnyObject, Selector, Int) -> Void
            unsafeBitCast(config.method(for: setTransport), to: SetFn.self)(config, setTransport, 2)
        }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, @escaping @convention(block) (NSError?) -> Void) -> Void
        unsafeBitCast(m.method(for: sel), to: Fn.self)(m, sel, device, config) { error in
            DispatchQueue.main.async { done(error) }
        }
    }

    static func describe(_ device: NSObject) -> String {
        let model = (device.value(forKey: "model") as? String) ?? "?"
        return "\(name(device)) [\(model)]"
    }

    func disconnect(_ device: NSObject, done: @escaping (Error?) -> Void) {
        call("disconnectFromDevice:completion:", device, done)
    }

    // MARK: private

    private func list(_ selector: String) -> [NSObject] {
        guard let m = manager, m.responds(to: Selector((selector))) else { return [] }
        return m.perform(Selector((selector)))?.takeUnretainedValue() as? [NSObject] ?? []
    }

    private typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (NSError?) -> Void) -> Void

    private func call(_ selector: String, _ device: NSObject, _ done: @escaping (Error?) -> Void) {
        let sel = Selector((selector))
        guard let m = manager, m.responds(to: sel) else {
            done(NSError(domain: "Tether", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sidecar API unavailable"]))
            return
        }
        let fn = unsafeBitCast(m.method(for: sel), to: Fn.self)
        fn(m, sel, device) { error in DispatchQueue.main.async { done(error) } }
    }
}
