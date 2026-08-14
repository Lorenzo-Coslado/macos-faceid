// SettingsView.swift — la fenêtre principale de Mugshot.
//
// C'est ce que voit l'utilisateur quand il ouvre l'app. Elle commence par répondre à la
// seule question qui compte — « est-ce que ça marche ? » — et met l'action qui débloque
// la situation juste à côté de la réponse. L'ancienne version alignait des réglages sans
// jamais dire si l'ensemble fonctionnait.
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @StateObject private var setup = SetupFlow()
    var onEnroll: (_ appending: Bool) -> Void
    var onApply: () -> Void          // redémarre le daemon avec le nouvel env

    @State private var sudoActive = Status.sudoActive
    @State private var enrolled = Status.enrolled
    @State private var busy = false
    @State private var note = ""
    @State private var showingSetup = false
    @State private var testResult: TestResult?
    // Listé une fois : brancher un iPhone pendant que la fenêtre est ouverte est rare,
    // et ré-interroger AVFoundation à chaque rendu réveillerait le téléphone.
    @State private var cameras = Cameras.list()

    struct TestResult { let ok: Bool; let detail: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            statusBanner
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    faceSection
                    sudoSection
                    behaviourSection
                    if !note.isEmpty {
                        Text(note).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            // Hors du défilement : ce sont des commandes de la fenêtre, pas du contenu.
            // Dans le ScrollView, « Désinstaller » restait sous la ligne de flottaison —
            // invisible à celui qui cherche justement comment s'en débarrasser.
            Divider()
            footer
        }
        .frame(width: 460, height: 620)
        .background(VisualEffect().ignoresSafeArea())
        .onAppear { refreshStatus() }
        .sheet(isPresented: $showingSetup) {
            SetupSheet(flow: setup) {
                showingSetup = false
                refreshStatus()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let img = Brand.logo() {
                Image(nsImage: img).resizable().frame(width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Mugshot").font(.system(size: 19, weight: .bold))
                Text(L("app.subtitle"))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    // ---- bandeau d'état ----
    // Une phrase, et le bouton qui règle le problème qu'elle décrit. C'est la seule
    // partie de la fenêtre qui compte quand quelque chose ne marche pas.
    private var statusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: bannerIcon)
                .font(.system(size: 18))
                .foregroundStyle(bannerReady ? Brand.green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle).font(.system(size: 13, weight: .semibold))
                Text(bannerDetail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let (label, action) = bannerAction {
                Button(label, action: action).tint(Brand.green)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private var bannerReady: Bool { enrolled && sudoActive }
    private var bannerIcon: String {
        bannerReady ? "checkmark.seal.fill" : "exclamationmark.circle.fill"
    }
    private var bannerTitle: String {
        if !enrolled { return L("banner.noface.title") }
        if !sudoActive { return L("banner.nosudo.title") }
        return L("banner.ready.title")
    }
    private var bannerDetail: String {
        if !enrolled { return L("banner.noface.detail") }
        if !sudoActive { return L("banner.nosudo.detail") }
        return L("banner.ready.detail")
    }
    private var bannerAction: (String, () -> Void)? {
        if !enrolled { return (L("set.face.setup"), { onEnroll(false) }) }
        if !sudoActive { return (L("banner.nosudo.action"), beginSetup) }
        return (L("banner.ready.action"), runTest)
    }

    // ---- section visage ----
    private var faceSection: some View {
        section(L("set.section.face")) {
            HStack {
                Label(enrolled ? L("set.face.yes") : L("set.face.no"),
                      systemImage: enrolled ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark")
                    .foregroundStyle(enrolled ? Brand.green : .secondary)
                Spacer()
                Button(enrolled ? L("set.face.reenroll") : L("set.face.setup")) {
                    onEnroll(false)
                }.tint(Brand.green)
            }
            if enrolled {
                // Comme les « apparences » du vrai Face ID : lunettes, barbe, lumière
                // du soir. Ré-enrôler remplaçait tout, donc s'adapter coûtait de
                // recommencer à zéro.
                HStack(spacing: 6) {
                    Button(L("set.face.append")) { onEnroll(true) }
                        .buttonStyle(.link).tint(Brand.green)
                    Text(L("set.face.append.desc"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            if let r = testResult {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(r.ok ? Brand.green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.ok ? L("notify.test.ok") : L("notify.test.fail"))
                            .font(.system(size: 12, weight: .medium))
                        // Le moteur renvoie score, nombre de visages vus et luminosité.
                        // Les afficher évite le « ça ne marche pas » sans indice.
                        Text(r.detail)
                            .font(.system(size: 10.5).monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // ---- section sudo ----
    private var sudoSection: some View {
        section(L("set.section.sudo")) {
            HStack {
                Label(sudoActive ? L("set.sudo.on") : L("set.sudo.off"),
                      systemImage: sudoActive ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(sudoActive ? Brand.green : .secondary)
                Spacer()
                if sudoActive {
                    Button(L("set.sudo.disable")) { disableSudo() }
                        .disabled(busy)
                } else {
                    Button(L("banner.nosudo.action"), action: beginSetup)
                        .tint(Brand.green).disabled(busy)
                }
            }
            Text(L("set.sudo.desc"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // ---- section comportement ----
    private var behaviourSection: some View {
        section(L("set.section.behavior")) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $settings.modal.onChange(applyDaemon)) {
                    Text(L("set.behavior.modal"))
                }.toggleStyle(.switch).tint(Brand.green)

                Toggle(isOn: $settings.hud.onChange(applyDaemon)) {
                    Text(L("set.behavior.hud"))
                }.toggleStyle(.switch).tint(Brand.green)

                if cameras.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(L("set.behavior.camera"),
                               selection: $settings.cameraIndex.onChange(applyDaemon)) {
                            Text(L("set.behavior.camera.auto")).tag(-1)
                            ForEach(cameras) { camera in
                                Text(camera.isContinuity
                                     ? String(format: L("set.behavior.camera.iphone"), camera.name)
                                     : camera.name).tag(camera.id)
                            }
                        }
                        Text(L("set.behavior.camera.desc"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                sensitivityControl

                Button {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                } label: {
                    Label(L("set.behavior.camera.system"), systemImage: "camera")
                }.buttonStyle(.link).tint(Brand.green)
            }
        }
    }

    /// Trois crans plutôt qu'une similarité cosinus brute : « 0,36 » ne veut rien dire
    /// pour qui n'a pas lu le code. La valeur exacte reste accessible en dessous.
    private var sensitivityControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(L("set.behavior.sensitivity"), selection: Binding(
                get: { Sensitivity.nearest(settings.threshold) },
                set: { settings.threshold = $0.threshold; applyDaemon() }
            )) {
                ForEach(Sensitivity.allCases) { level in
                    Text(L(level.labelKey)).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(L(Sensitivity.nearest(settings.threshold).detailKey))
                .font(.system(size: 11)).foregroundStyle(.secondary)

            DisclosureGroup(L("set.behavior.sensitivity.advanced")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("set.behavior.sensitivity"))
                        Spacer()
                        Text(String(format: "%.2f", settings.threshold))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    // Appliqué au relâchement seulement. Avec .onChange, glisser le
                    // curseur redémarrait le moteur à chaque incrément — une dizaine
                    // de processus lancés puis tués, se disputant la même socket.
                    Slider(value: $settings.threshold,
                           in: 0.30...0.50, step: 0.01,
                           onEditingChanged: { editing in
                               if !editing { applyDaemon() }
                           }).tint(Brand.green)
                    Text(L("set.behavior.sensitivity.desc"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11.5))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(L("set.diagnose")) { copyDiagnostics() }
                .buttonStyle(.link).tint(Brand.green)
            Spacer()
            Button(L("uninstall.action")) { confirmUninstall() }
                .buttonStyle(.link).tint(.red)
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    // ---- actions ----
    private func refreshStatus() {
        sudoActive = Status.sudoActive
        enrolled = Status.enrolled
    }

    private func applyDaemon() { onApply() }

    private func beginSetup() {
        note = ""
        setup.reset()
        showingSetup = true
        setup.start()
    }

    private func disableSudo() {
        busy = true; note = ""
        HelperManager.shared.disableSudo { ok, msg in
            busy = false
            note = ok ? L("set.msg.sudo.off") : String(format: L("set.msg.cancelled"), msg)
            refreshStatus()
        }
    }

    private func runTest() {
        testResult = nil
        DispatchQueue.global().async {
            let r = Run.faceid(["verify"])
            let out = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                testResult = TestResult(ok: out.contains("OK"), detail: out)
            }
        }
    }

    /// Le rapport que `diagnose.sh` produit, dans le presse-papiers. C'est exactement
    /// ce qu'on demande de coller dans un ticket, et il n'était accessible qu'en
    /// clonant le dépôt.
    private func copyDiagnostics() {
        note = L("set.diagnose.running")
        DispatchQueue.global().async {
            let out = Run.bashUser("bash \(shq(Paths.script("diagnose.sh"))) "
                                   + shq(Bundle.main.bundleURL.path)).out
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(out, forType: .string)
                note = L("set.diagnose.copied")
            }
        }
    }

    private func shq(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // ---- désinstallation ----
    private func confirmUninstall() {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = L("uninstall.confirm.title")
        a.informativeText = L("uninstall.confirm.body")
        a.addButton(withTitle: L("uninstall.confirm.ok"))
        a.addButton(withTitle: L("fda.cancel"))

        // Case décochée par défaut : effacer le visage enrôlé est irréversible, et
        // quelqu'un qui réinstalle demain préfère ne pas recommencer l'enrôlement.
        let box = NSButton(checkboxWithTitle: L("uninstall.confirm.data"),
                           target: nil, action: nil)
        box.state = .off
        a.accessoryView = box

        guard a.runModal() == .alertFirstButtonReturn else { return }

        busy = true
        note = L("uninstall.running")
        Uninstaller.run(deleteData: box.state == .on) { outcome in
            busy = false
            if let failure = outcome.failure {
                note = String(format: L("uninstall.failed"), failure)
                refreshStatus()
                return
            }
            let done = NSAlert()
            done.messageText = L("uninstall.done.title")
            done.informativeText = outcome.steps.map { "• \($0)" }.joined(separator: "\n")
                + "\n\n" + L("uninstall.done.body")
            done.addButton(withTitle: L("uninstall.done.trash"))
            done.addButton(withTitle: L("onb.close"))
            if done.runModal() == .alertFirstButtonReturn {
                Uninstaller.trashAppAndQuit()
            } else {
                Uninstaller.quitOnly()
            }
        }
    }
}

/// Crans de sensibilité exposés à l'utilisateur, adossés au seuil cosinus réel.
enum Sensitivity: String, CaseIterable, Identifiable {
    case lenient, balanced, strict

    var id: String { rawValue }

    var threshold: Double {
        switch self {
        case .lenient:  return 0.33
        case .balanced: return 0.36     // référence OpenCV Zoo (0.363)
        case .strict:   return 0.42
        }
    }
    var labelKey: String { "set.sensitivity.\(rawValue)" }
    var detailKey: String { "set.sensitivity.\(rawValue).detail" }

    /// Le cran le plus proche d'un seuil quelconque : un réglage fait au curseur
    /// avancé doit rester représentable dans le sélecteur.
    static func nearest(_ value: Double) -> Sensitivity {
        allCases.min(by: { abs($0.threshold - value) < abs($1.threshold - value) }) ?? .balanced
    }
}

// Petit utilitaire : exécuter une closure quand un Binding change.
extension Binding {
    func onChange(_ action: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue },
                set: { newValue in wrappedValue = newValue; action() })
    }
}
