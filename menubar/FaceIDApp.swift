// FaceIDApp — app menu bar complète : menu brandé, fenêtres d'enrôlement et de
// réglages, supervision du daemon Face ID.
import AppKit
import SwiftUI
import ServiceManagement
import Sparkle

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
/// Résume l'état en une ligne compréhensible. L'en-tête disait « Daemon running », ce
/// qui renseigne sur un processus et pas sur la question posée : est-ce que `sudo` va
/// reconnaître mon visage ?
struct MenuHeader: View {
    var running: Bool

    private var ready: Bool { running && Status.enrolled && Status.sudoActive }
    private var label: String {
        if !running { return L("menu.status.stopped") }
        if !Status.enrolled { return L("menu.status.noface") }
        if !Status.sudoActive { return L("menu.status.nosudo") }
        return L("menu.status.ready")
    }

    var body: some View {
        HStack(spacing: 11) {
            if let img = Brand.logo() {
                Image(nsImage: img).resizable().frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Mugshot").font(.system(size: 14, weight: .bold))
                HStack(spacing: 5) {
                    Circle().fill(ready ? Brand.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(label)
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
    // Auto-update : démarre le vérificateur (check périodique via SUEnableAutomaticChecks).
    let updater = SPUStandardUpdaterController(startingUpdater: true,
                                               updaterDelegate: nil, userDriverDelegate: nil)
    var onboardingWC: NSWindowController?
    var settingsWC: NSWindowController?

    func applicationDidFinishLaunching(_ n: Notification) {
        warnIfRunningFromAnUnstableLocation()
        daemon.onExit = { [weak self] in self?.refresh() }
        if let b = statusItem.button {
            if let p = Bundle.main.path(forResource: "menubar-icon", ofType: "png"),
               let img = NSImage(contentsOfFile: p) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                b.image = img
            }
            b.imagePosition = .imageOnly
            b.toolTip = "Mugshot"
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

        // Ouvrir l'app doit montrer quelque chose. Une app de barre de menus qui se
        // lance sans rien afficher laisse croire qu'elle n'a pas démarré — sauf quand
        // c'est macOS qui l'ouvre à l'ouverture de session, où surgir devant
        // l'utilisateur serait au contraire déplacé. `launchIsDefaultUserInfoKey`
        // distingue précisément les deux cas.
        let userLaunched = n.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if userLaunched {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // Sans visage enrôlé, l'enrôlement est la seule chose à faire : on y va
                // directement plutôt que d'afficher des réglages inertes.
                if Status.enrolled { self.openSettings() } else { self.openOnboarding() }
            }
        }
        // Drapeaux internes pour régénérer les captures de la documentation. Sans eux,
        // l'écran d'enrôlement ne s'ouvre qu'en l'absence de visage enregistré, donc
        // impossible à photographier sur une machine où l'app est déjà configurée.
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openSettings() }
        }
        if CommandLine.arguments.contains("--open-enrollment") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openOnboarding() }
        }
    }

    func applicationWillTerminate(_ n: Notification) { daemon.stop() }

    /// Quitter Mugshot arrête le moteur, donc `sudo` redemande le mot de passe — sans
    /// que rien ne le dise. Le moteur doit rester un processus enfant de l'app : lancé
    /// par launchd, macOS attribuerait la demande caméra au binaire du moteur, qui n'a
    /// pas de `NSCameraUsageDescription`, et la refuserait sans même afficher de
    /// dialogue (c'est le problème que documente scripts/fix-camera-launchd.sh). La
    /// seule chose qu'on puisse corriger, c'est le silence.
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        guard Status.sudoActive, !AppController.suppressQuitWarning else { return .terminateNow }
        // Ne jamais interroger l'utilisateur quand c'est macOS qui ferme la session : une
        // alerte modale à ce moment-là bloque la déconnexion ou l'extinction, et macOS
        // finit par accuser l'app d'empêcher la fermeture.
        guard !isSystemInitiatedQuit else { return .terminateNow }
        let a = NSAlert()
        a.messageText = L("quit.title")
        a.informativeText = L("quit.body")
        a.addButton(withTitle: L("quit.confirm"))
        a.addButton(withTitle: L("quit.cancel"))
        return a.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// La désinstallation quitte volontairement : elle ne doit pas déclencher la mise
    /// en garde ci-dessus, puisqu'elle vient précisément de retirer la règle sudo.
    static var suppressQuitWarning = false

    /// Vrai quand la demande d'arrêt vient d'une déconnexion, d'un redémarrage ou d'une
    /// extinction. L'AppleEvent qui accompagne `quit` porte alors une raison ; un
    /// « Quitter » ordinaire n'en porte aucune.
    private var isSystemInitiatedQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))
        else { return false }
        let systemReasons: [OSType] = [
            OSType(kAELogOut), OSType(kAEReallyLogOut),
            OSType(kAEShowRestartDialog), OSType(kAERestart),
            OSType(kAEShowShutdownDialog), OSType(kAEShutDown),
        ]
        return systemReasons.contains(reason.enumCodeValue)
    }

    /// Recliquer sur l'icône dans le Dock, Spotlight ou le Finder alors que l'app
    /// tourne déjà. Sans ceci, le second lancement ne produisait rien du tout.
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    // App menu bar : ne jamais quitter parce qu'une fenêtre se ferme.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    // ---------- menu ----------
    func refresh() { buildMenu(running: daemon.isRunning) }

    /// Running from the mounted disk image or the Downloads folder half-works: enrolment
    /// and settings behave, but the privileged helper gets registered from a path that
    /// moves or disappears, and sudo then quietly falls back to the password. Say so
    /// before the user spends time setting things up.
    private func warnIfRunningFromAnUnstableLocation() {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let inApplications = path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        guard !inApplications else { return }

        let onReadOnlyImage = path.hasPrefix("/Volumes/")
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = L("move.title")
        a.informativeText = onReadOnlyImage ? L("move.body.dmg") : L("move.body.other")
        // Proposer de le faire, plutôt que d'expliquer le problème et de laisser
        // l'utilisateur s'en charger. Le bouton par défaut agit.
        a.addButton(withTitle: L("move.doit"))
        a.addButton(withTitle: L("move.reveal"))
        a.addButton(withTitle: L("move.ignore"))
        switch a.runModal() {
        case .alertFirstButtonReturn:  moveToApplicationsAndRelaunch()
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        default: break
        }
    }

    /// Copie le bundle dans /Applications, relance depuis là, et se termine. La copie
    /// plutôt que le déplacement : sur une image disque en lecture seule, déplacer est
    /// impossible, et laisser l'original en place ne coûte rien.
    private func moveToApplicationsAndRelaunch() {
        let src = Bundle.main.bundleURL
        let dst = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(src.lastPathComponent)
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
        } catch {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = L("move.failed")
            a.informativeText = error.localizedDescription
            a.runModal()
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dst, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func buildMenu(running: Bool) {
        let m = NSMenu()

        let header = NSMenuItem()
        let hv = NSHostingView(rootView: MenuHeader(running: running))
        hv.frame = NSRect(x: 0, y: 0, width: 240, height: 54)
        header.view = hv
        m.addItem(header)
        m.addItem(.separator())

        // « Ouvrir » en premier : c'est l'action attendue quand on déroule le menu.
        m.addItem(item(L("menu.open"), #selector(openSettings), "o"))
        m.addItem(item(Status.enrolled ? L("menu.enroll.reenroll") : L("menu.enroll.setup"),
                       #selector(openOnboarding), "f"))

        // Réparation, pas interrupteur. Le menu proposait « Arrêter le service », qui
        // coupait Face ID pour sudo d'un clic sans que rien ne le dise.
        if !running {
            m.addItem(.separator())
            m.addItem(item(L("menu.restart"), #selector(startDaemon)))
        }

        m.addItem(.separator())

        // Item géré par Sparkle (activation/désactivation auto pendant un check).
        let upd = NSMenuItem(title: L("menu.update"),
                             action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                             keyEquivalent: "")
        upd.target = updater
        m.addItem(upd)

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
    @objc func openOnboarding() { openEnrollment(appending: false) }

    func openEnrollment(appending: Bool) {
        enroll.reset(appending: appending)
        if onboardingWC == nil {
            let view = OnboardingView(c: enroll) { [weak self] in
                guard let self else { return }
                self.onboardingWC?.close()
                self.refresh()
                // Enchaîner sur la fenêtre principale : une fois le visage enregistré,
                // il reste à brancher sudo, et le bandeau d'état le dit avec le bouton
                // qui le fait. L'écran de fin se contentait d'écrire « vous pouvez
                // maintenant activer Face ID dans les réglages » et laissait chercher.
                if Status.enrolled { self.openSettings() }
            }
            let win = brandedWindow(width: 440, height: 500, titled: false)
            win.contentView = NSHostingView(rootView: view)
            onboardingWC = NSWindowController(window: win)
        }
        present(onboardingWC)
    }

    @objc func openSettings() {
        if settingsWC == nil {
            let view = SettingsView(onEnroll: { [weak self] appending in
                                        self?.openEnrollment(appending: appending)
                                    },
                                    onApply: { [weak self] in self?.restartDaemon() })
            let win = brandedWindow(width: 460, height: 620, titled: true)
            win.title = "Mugshot"
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
    @objc func stopDaemon() { daemon.stop(); refresh() }   // conservé pour --refresh-helper

    /// Redémarrage sérialisé : un appel rapproché annule le démarrage encore en
    /// attente. Sans cela, plusieurs `start` différés se déclenchaient à la suite et
    /// plusieurs moteurs se disputaient la même socket.
    private var pendingRestart: DispatchWorkItem?

    func restartDaemon() {
        pendingRestart?.cancel()
        daemon.stop()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.daemon.env = Settings.shared.env
            self.daemon.start()
            self.refresh()
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
            } catch {
                // Une alerte plutôt qu'une notification : NSUserNotification est
                // dépréciée et n'affiche rien si les notifications ne sont pas
                // autorisées — l'erreur disparaissait donc en silence.
                let a = NSAlert()
                a.alertStyle = .warning
                a.messageText = L("menu.login")
                a.informativeText = error.localizedDescription
                a.runModal()
            }
            refresh()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

@main
struct FaceIDMain {
    static func main() {
        if CommandLine.arguments.contains("--refresh-helper") {
            switch HelperManager.shared.refreshRegistration() {
            case .enabled:
                print("helper enregistré et activé")
                exit(0)
            case .needsApproval:
                print("helper enregistré; approbation requise dans Réglages > Éléments d'ouverture")
                exit(3)
            case .failed(let message):
                fputs("échec de l'enregistrement du helper : \(message)\n", stderr)
                exit(1)
            }
        }
        if CommandLine.arguments.contains("--probe-helper") {
            var result: Int32?
            HelperManager.shared.probe { ok, message in
                print(message)
                result = ok ? 0 : 1
            }
            let deadline = Date().addingTimeInterval(8)
            while result == nil && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            if result == nil { fputs("helper probe timeout\n", stderr) }
            exit(result ?? 2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = AppController()
        app.delegate = controller
        app.run()
    }
}
