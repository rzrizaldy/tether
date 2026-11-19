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

    func connect(_ device: NSObject, done: @escaping (Error?) -> Void) {
        call("connectToDevice:completion:", device, done)
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
