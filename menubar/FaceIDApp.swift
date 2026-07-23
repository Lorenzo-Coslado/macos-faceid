// FaceIDApp — app menu bar complète : menu brandé, fenêtres d'enrôlement et de
// réglages, supervision du daemon Face ID.
import AppKit
import SwiftUI
import ServiceManagement

// ---------- supervision du daemon ----------
final class DaemonController {
    private var proc: Process?
    var env: [String: String] = [:]
    var onExit: (() -> Void)?

    var isRunning: Bool { proc?.isRunning ?? false }

    func start() {
        guard !isRunning else { return }
        let (exe, args) = Run.faceidCmd(["daemon"])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if !Paths.bundled {   // dev : cwd = projet pour que `python -m faceid` résolve
            p.currentDirectoryURL = URL(fileURLWithPath: Paths.root)
        }
        var e = ProcessInfo.processInfo.environment
        e["PYTHONUNBUFFERED"] = "1"
        e.merge(Paths.childEnv) { _, n in n }
        e.merge(env) { _, n in n }
        p.environment = e
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.onExit?() }
        }
        do { try p.run(); proc = p }
        catch { NSLog("faceid: échec démarrage daemon: \(error)") }
    }

    func stop() { proc?.terminate(); proc = nil }
}

// ---------- en-tête brandé du menu ----------
struct MenuHeader: View {
    var running: Bool
    var body: some View {
        HStack(spacing: 11) {
            if let img = Brand.logo() {
                Image(nsImage: img).resizable().frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("FaceID").font(.system(size: 14, weight: .bold))
                HStack(spacing: 5) {
                    Circle().fill(running ? Brand.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(running ? L("menu.daemon.running") : L("menu.daemon.stopped"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(width: 240)
    }
}

// ---------- contrôleur principal ----------
final class AppController: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let daemon = DaemonController()
    let enroll = EnrollController()
    var onboardingWC: NSWindowController?
    var settingsWC: NSWindowController?

    func applicationDidFinishLaunching(_ n: Notification) {
        daemon.onExit = { [weak self] in self?.refresh() }
        if let b = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let img = NSImage(systemSymbolName: "faceid", accessibilityDescription: "FaceID")?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = true
            b.image = img
            b.imagePosition = .imageOnly
            b.toolTip = "FaceID"
        }
        daemon.env = Settings.shared.env
        daemon.start()
        refresh()

        // Auto-inscription au démarrage (une seule fois) : l'app + le daemon se
        // lanceront à l'ouverture de session. Réversible via le menu.
        if #available(macOS 13.0, *) {
            let key = "faceid.autoLoginRegistered"
            if !UserDefaults.standard.bool(forKey: key) {
                try? SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: key)
            }
        }

        // Premier lancement sans visage enrôlé : propose la configuration.
        if !Status.enrolled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.openOnboarding() }
        }
    }

    func applicationWillTerminate(_ n: Notification) { daemon.stop() }

    // App menu bar : ne jamais quitter parce qu'une fenêtre se ferme.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    // ---------- menu ----------
    func refresh() { buildMenu(running: daemon.isRunning) }

    func buildMenu(running: Bool) {
        let m = NSMenu()

        let header = NSMenuItem()
        let hv = NSHostingView(rootView: MenuHeader(running: running))
        hv.frame = NSRect(x: 0, y: 0, width: 240, height: 54)
        header.view = hv
        m.addItem(header)
        m.addItem(.separator())

        m.addItem(item(Status.enrolled ? L("menu.enroll.reenroll") : L("menu.enroll.setup"),
                       #selector(openOnboarding), "f"))
        m.addItem(item(L("menu.test"), #selector(testVerify), "t"))

        m.addItem(.separator())
        if running { m.addItem(item(L("menu.daemon.stop"), #selector(stopDaemon))) }
        else { m.addItem(item(L("menu.daemon.start"), #selector(startDaemon))) }
        m.addItem(item(L("menu.settings"), #selector(openSettings), ","))

        m.addItem(.separator())
        let login = item(L("menu.login"), #selector(toggleLogin))
        login.state = loginEnabled ? .on : .off
        m.addItem(login)

        m.addItem(.separator())
        m.addItem(item(L("menu.quit"), #selector(quit), "q"))

        statusItem.menu = m
    }

    func item(_ title: String, _ sel: Selector, _ key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    // ---------- fenêtres ----------
    @objc func openOnboarding() {
        enroll.reset()
        if onboardingWC == nil {
            let view = OnboardingView(c: enroll) { [weak self] in
                self?.onboardingWC?.close()
                self?.refresh()
            }
            let win = brandedWindow(width: 440, height: 500, titled: false)
            win.contentView = NSHostingView(rootView: view)
            onboardingWC = NSWindowController(window: win)
        }
        present(onboardingWC)
    }

    @objc func openSettings() {
        if settingsWC == nil {
            let view = SettingsView(onEnroll: { [weak self] in self?.openOnboarding() },
                                    onApply: { [weak self] in self?.restartDaemon() })
            let win = brandedWindow(width: 460, height: 560, titled: true)
            win.title = L("set.title")
            win.contentView = NSHostingView(rootView: view)
            settingsWC = NSWindowController(window: win)
        }
        present(settingsWC)
    }

    func brandedWindow(width: CGFloat, height: CGFloat, titled: Bool) -> NSWindow {
        let style: NSWindow.StyleMask = titled
            ? [.titled, .closable]
            : [.titled, .closable, .fullSizeContentView]
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                           styleMask: style, backing: .buffered, defer: false)
        if !titled {
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
        }
        win.center()
        win.isReleasedWhenClosed = false
        return win
    }

    func present(_ wc: NSWindowController?) {
        NSApp.activate(ignoringOtherApps: true)
        wc?.showWindow(nil)
        wc?.window?.makeKeyAndOrderFront(nil)
    }

    // ---------- actions daemon ----------
    @objc func startDaemon() {
        daemon.env = Settings.shared.env
        daemon.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }
    @objc func stopDaemon() { daemon.stop(); refresh() }

    func restartDaemon() {
        daemon.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.daemon.env = Settings.shared.env
            self.daemon.start()
            self.refresh()
        }
    }

    @objc func testVerify() {
        DispatchQueue.global().async {
            let r = Run.faceid(["verify"])
            let ok = r.out.contains("OK")
            DispatchQueue.main.async {
                self.notify(L("notify.test.title"), ok ? L("notify.test.ok") : L("notify.test.fail"))
            }
        }
    }

    // ---------- login item ----------
    var loginEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    @objc func toggleLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch { notify("Démarrage", "Erreur : \(error.localizedDescription)") }
            refresh()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }

    func notify(_ title: String, _ body: String) {
        let n = NSUserNotification()
        n.title = title; n.informativeText = body
        NSUserNotificationCenter.default.deliver(n)
    }
}

@main
struct FaceIDMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = AppController()
        app.delegate = controller
        app.run()
    }
}
