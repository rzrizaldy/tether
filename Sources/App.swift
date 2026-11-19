import AppKit
import ServiceManagement

@main
@MainActor
final class Tether: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = Tether()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let sidecar = Sidecar()
    private let usb = USBWatcher()
    private let pointer = PadPointer()
    private let screen = VirtualScreen()
    private let defaults = UserDefaults.standard
    private var item: NSStatusItem!
    private var timer: Timer?

    private var connectingSince: Date?
    private var sawSidecarThisPlug = false
    private var userDisconnected = false
    private var wantMain = false
    private var lastError: String?
    private var attempt = 0
    /// Backoff so a Sidecar that keeps dropping isn't hammered every 4 seconds.
    private var wasConnected = false
    private var connectedAt = Date.distantPast
    private var drops = 0
    private var nextConnect = Date.distantPast

    private var autoConnect: Bool { get { defaults.bool(forKey: "autoConnect") } set { defaults.set(newValue, forKey: "autoConnect") } }
    private var lidClosed: Bool { get { defaults.bool(forKey: "lidClosed") } set { defaults.set(newValue, forKey: "lidClosed") } }
    private var makeMain: Bool { get { defaults.bool(forKey: "makeMain") } set { defaults.set(newValue, forKey: "makeMain") } }
    /// Sill (getsill.app) carries the picture when there's no cable: over Wi-Fi
    /// at home, or through Tailscale from away. Sidecar stays the cable's.
    private static let sillID = "me.saffer.sill.mac"
    private var sillInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.sillID) != nil }
    private var sillOpened = false
    private var remote: Bool { get { defaults.bool(forKey: "remote") } set { defaults.set(newValue, forKey: "remote") } }
    private var bigCursor: Bool { get { defaults.bool(forKey: "bigCursor") } set { defaults.set(newValue, forKey: "bigCursor") } }
    /// Set by 1.2 builds that enlarged the pointer; put back on launch.
    private var savedCursor: Float { get { defaults.float(forKey: "savedCursor") } set { defaults.set(newValue, forKey: "savedCursor") } }
    /// Persisted so a crash never leaves the Mac unable to sleep in your bag.
    private var awakeHeld: Bool { get { defaults.bool(forKey: "awakeHeld") } set { defaults.set(newValue, forKey: "awakeHeld") } }

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        defaults.register(defaults: ["autoConnect": true, "lidClosed": true, "makeMain": true, "bigCursor": true])

        if awakeHeld { Power.keepAwakeWithLidClosed(false); awakeHeld = false }
        if savedCursor > 0 { Cursor.scale = savedCursor; savedCursor = 0 }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.write("Tether \(version) started on macOS \(ProcessInfo.processInfo.operatingSystemVersionString). Sidecar \(sidecar.isAvailable ? "found" : "MISSING"), lid-closed \(Power.isSetUp ? "set up" : "not set up")")

        if !defaults.bool(forKey: "didSetUpLogin") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "didSetUpLogin")
        }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        usb.onChange = { [weak self] in self?.evaluate() }
        usb.start()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.placeMenuBarOnPad()
                self?.pointer.screenFrame = self?.padScreenFrame()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        evaluate()
    }

    func applicationWillTerminate(_ note: Notification) {
        if awakeHeld { Power.keepAwakeWithLidClosed(false); awakeHeld = false }
        pointer.hide()
        screen.hide()
    }

    // MARK: the whole brain

    private func evaluate() {
        let plugged = usb.iPadPlugged
        let connected = sidecar.isConnected

        if !plugged { sawSidecarThisPlug = false; userDisconnected = false; drops = 0; nextConnect = .distantPast }
        if plugged && connected { sawSidecarThisPlug = true }

        if connected && !wasConnected { connectedAt = Date() }
        if !connected && wasConnected && plugged && !userDisconnected {
            let held = Date().timeIntervalSince(connectedAt)
            drops = held < 20 ? drops + 1 : 0
            let wait = min(30, 2 * pow(2, Double(drops)))
            nextConnect = Date().addingTimeInterval(wait)
            Log.write("Sidecar dropped after \(Int(held))s; next try in \(Int(wait))s")
        }
        wasConnected = connected

        // Sidecar hides the Mac's pointer on the iPad; draw it ourselves.
        let wantPointer = bigCursor && connected
        if wantPointer {
            pointer.screenFrame = padScreenFrame()
            if !pointer.isOn { pointer.show() }
        } else if pointer.isOn {
            pointer.hide()
        }

        // Remote mode: a virtual Retina screen for Screen Sharing, unless the
        // iPad is right here on Sidecar, in which case that is the screen.
        let wantScreen = remote && !connected
        // Remote with Sill: no Sidecar, so make sure Sill is there to stream.
        if wantScreen && sillInstalled && !sillOpened { openSill(); sillOpened = true }
        if !wantScreen { sillOpened = false }
        if wantScreen && !screen.isOn {
            screen.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.placeMenuBarOnVirtual() }
        } else if !wantScreen && screen.isOn {
            screen.hide()
        }

        // Cable in + iPad has been the screen → survive the lid closing.
        // Remote mode on a charger → stay up so you can reach the Mac from away.
        let wantAwake = (lidClosed && plugged && sawSidecarThisPlug && !userDisconnected)
            || (remote && lidClosed && Remote.onCharger)
        if wantAwake != awakeHeld {
            let ok = Power.keepAwakeWithLidClosed(wantAwake)
            Log.write("Lid-closed awake → \(wantAwake ? "on" : "off") \(ok ? "" : Power.isSetUp ? "(pmset failed)" : "(not set up yet)")")
            if ok || !Power.isSetUp { awakeHeld = wantAwake && Power.isSetUp }
        }

        if let since = connectingSince, Date().timeIntervalSince(since) > 30 { connectingSince = nil }
        if plugged && autoConnect && !userDisconnected && !connected && connectingSince == nil && Date() >= nextConnect {
            connect()
        }
        refreshIcon()
    }

    private func connect() {
        guard let device = sidecar.devices.first else {
            let why = sidecar.isAvailable ? "iPad not found — unlock it and check Apple ID" : "Sidecar unavailable on this Mac"
            if lastError != why { Log.write("Can't connect: \(why)") }
            lastError = why
            return
        }
        // With the cable in, force the wired link first; every other try,
        // let Sidecar choose, in case this macOS rejects the wired config.
        attempt += 1
        let wired = usb.iPadPlugged && attempt % 2 == 1
        connectingSince = Date()
        refreshIcon()
        Log.write("Connect #\(attempt) to \(Sidecar.describe(device)) \(wired ? "over the cable" : "(Sidecar picks the link)")")
        sidecar.connect(device, wired: wired) { [weak self] error in
            guard let self else { return }
            self.connectingSince = nil
            self.lastError = error?.localizedDescription
            if let e = error as NSError? {
                Log.write("  failed: \(e.domain) \(e.code) — \(e.localizedDescription)")
            } else {
                Log.write("  connected. Sidecar reports \(self.sidecar.connected.count) connected device(s)")
                self.attempt = 0
                self.wantMain = true
                self.placeMenuBarOnPad()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.placeMenuBarOnPad() }
            }
            self.evaluate()
        }
    }

    private func disconnect() {
        userDisconnected = true
        for d in sidecar.connected { sidecar.disconnect(d) { [weak self] _ in self?.evaluate() } }
        evaluate()
    }

    /// Only take the menu bar when no real monitor is around to keep it.
    private func placeMenuBarOnVirtual() {
        guard let id = screen.displayID, makeMain else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        let others = ids.prefix(Int(count)).filter { $0 != id && CGDisplayIsBuiltin($0) == 0 }
        if others.isEmpty { Displays.makeMain(id) }
    }

    private func padScreenFrame() -> NSRect? {
        guard let device = sidecar.connected.first,
              let id = Displays.sidecarDisplay(named: Sidecar.name(device)) else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }?.frame
    }

    private func placeMenuBarOnPad() {
        guard wantMain, makeMain, let device = sidecar.connected.first,
              let id = Displays.sidecarDisplay(named: Sidecar.name(device)) else { return }
        if Displays.makeMain(id) { wantMain = false }
    }

    // MARK: menu bar

    private func refreshIcon() {
        guard let button = item?.button else { return }
        let connected = sidecar.isConnected
        let symbol = connected ? "ipad.landscape.badge.play" : "ipad.landscape"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tether")
            ?? NSImage(systemSymbolName: "ipad.landscape", accessibilityDescription: "Tether")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !connected && !usb.iPadPlugged
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let connected = sidecar.connected.first
        let status: String
        if let d = connected { status = "\(Sidecar.name(d)) · Connected" }
        else if connectingSince != nil { status = "Connecting…" }
        else if usb.iPadPlugged, let e = lastError { status = e }
        else if usb.iPadPlugged { status = "iPad plugged in" }
        else { status = "Plug in your iPad" }
        menu.addItem(label(status))
        if awakeHeld { menu.addItem(label("Lid can be closed")) }
        if remote {
            let name = Remote.tailscaleName()
            menu.addItem(label(connected != nil ? "Remote: paused, the cable is on Sidecar" : Remote.onCharger ? (sillInstalled ? "Remote: ready in Sill" : "Remote: ready") : "Remote: plug in the charger to stay awake"))
            if sillInstalled {
                menu.addItem(action("Open Sill", #selector(tapOpenSill)))
            } else {
                if !Remote.screenSharingOn { menu.addItem(action("Turn On Screen Sharing…", #selector(tapSharing))) }
                if let name {
                    let i = action("Copy vnc://\(name)", #selector(tapCopyAddress))
                    i.representedObject = "vnc://\(name)"
                    menu.addItem(i)
                }
            }
            if name == nil { menu.addItem(action("Set Up Tailscale…", #selector(tapTailscale))) }
        }

        menu.addItem(.separator())
        if connected != nil {
            menu.addItem(action("Disconnect", #selector(tapDisconnect)))
        } else {
            menu.addItem(action("Connect Now", #selector(tapConnect), enabled: connectingSince == nil))
        }

        menu.addItem(.separator())
        menu.addItem(toggle("Auto-connect on cable", autoConnect, #selector(tapAuto)))
        menu.addItem(toggle(Power.isSetUp ? "Work with lid closed" : "Work with lid closed…", lidClosed && Power.isSetUp, #selector(tapLid)))
        menu.addItem(toggle("iPad as main display", makeMain, #selector(tapMain)))
        menu.addItem(toggle("Show pointer on iPad", bigCursor, #selector(tapCursor)))
        // With Sill installed, remote is a plain option. Without it (Screen
        // Sharing and a VNC app) it's experimental: shown with ⌥ held, or once on.
        if sillInstalled {
            menu.addItem(toggle("Remote and wireless with Sill", remote, #selector(tapRemote)))
        } else if remote || NSEvent.modifierFlags.contains(.option) {
            menu.addItem(toggle("Remote mode (experimental)", remote, #selector(tapRemote)))
        }
        menu.addItem(toggle("Open at login", SMAppService.mainApp.status == .enabled, #selector(tapLogin)))

        menu.addItem(.separator())
        menu.addItem(action("Open Log", #selector(tapLog)))
        menu.addItem(action("Quit Tether", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func label(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func action(_ title: String, _ sel: Selector, enabled: Bool = true, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = sel == #selector(NSApplication.terminate(_:)) ? NSApp : self
        i.isEnabled = enabled
        return i
    }

    private func toggle(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let i = action(title, sel)
        i.state = on ? .on : .off
        return i
    }

    @objc private func tapLog() { NSWorkspace.shared.open(Log.url) }
    @objc private func tapConnect() { userDisconnected = false; drops = 0; nextConnect = .distantPast; connect() }
    @objc private func tapDisconnect() { disconnect() }
    @objc private func tapOpenSill() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.sillID) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openSill() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.sillID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        Log.write("Opened Sill")
    }

    @objc private func tapRemote() { remote.toggle(); Log.write("Remote mode \(remote ? "on" : "off")"); evaluate() }
    @objc private func tapSharing() { Remote.openSharingSettings() }
    @objc private func tapTailscale() {
        let app = URL(fileURLWithPath: "/Applications/Tailscale.app")
        if FileManager.default.fileExists(atPath: app.path) { NSWorkspace.shared.open(app) }
        else if let url = URL(string: "https://tailscale.com/download/mac") { NSWorkspace.shared.open(url) }
    }
    @objc private func tapCopyAddress(_ sender: NSMenuItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sender.representedObject as? String ?? "", forType: .string)
    }
    @objc private func tapCursor() { bigCursor.toggle(); evaluate() }
    @objc private func tapAuto() { autoConnect.toggle(); evaluate() }
    @objc private func tapMain() { makeMain.toggle(); if makeMain { wantMain = true; placeMenuBarOnPad() } }

    @objc private func tapLid() {
        if !Power.isSetUp {
            NSApp.activate(ignoringOtherApps: true)
            guard Power.install() else { return }
            lidClosed = true
        } else {
            lidClosed.toggle()
        }
        evaluate()
    }

    @objc private func tapLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
    }
}
