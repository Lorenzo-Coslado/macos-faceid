// SettingsView.swift — réglages natifs de l'app (SwiftUI).
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    var onEnroll: () -> Void
    var onApply: () -> Void          // redémarre le daemon avec le nouvel env

    @State private var sudoActive = Status.sudoActive
    @State private var enrolled = Status.enrolled
    @State private var busy = false
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
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
        }
        .frame(width: 460, height: 560)
        .background(VisualEffect().ignoresSafeArea())
        .onAppear { refreshStatus() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let img = Brand.logo() {
                Image(nsImage: img).resizable().frame(width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("FaceID").font(.system(size: 19, weight: .bold))
                Text(L("app.subtitle"))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    // ---- section visage ----
    private var faceSection: some View {
        section(L("set.section.face")) {
            HStack {
                Label(enrolled ? L("set.face.yes") : L("set.face.no"),
                      systemImage: enrolled ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark")
                    .foregroundStyle(enrolled ? Brand.green : .secondary)
                Spacer()
                Button(enrolled ? L("set.face.reenroll") : L("set.face.setup"), action: onEnroll)
                    .tint(Brand.green)
            }
        }
    }

    // ---- section sudo ----
    private var sudoSection: some View {
        section(L("set.section.sudo")) {
            Toggle(isOn: Binding(
                get: { sudoActive },
                set: { want in toggleSudo(want) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("set.sudo.toggle"))
                    Text(L("set.sudo.desc"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).tint(Brand.green).disabled(busy)
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("set.behavior.sensitivity"))
                        Spacer()
                        Text(String(format: "%.2f", settings.threshold))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.threshold.onChange(applyDaemon),
                           in: 0.30...0.50, step: 0.01).tint(Brand.green)
                    Text(L("set.behavior.sensitivity.desc"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Button {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                } label: {
                    Label(L("set.behavior.camera"), systemImage: "camera")
                }.buttonStyle(.link).tint(Brand.green)
            }
        }
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

    // Active/désactive sudo via le daemon root (SMAppService + XPC). L'ancienne
    // voie osascript est cassée sur macOS 26 (authtrampoline → écriture refusée).
    private func toggleSudo(_ want: Bool) {
        busy = true; note = ""
        // Dev : compiler le module d'abord (hors main). Bundle : déjà précompilé.
        if want && !Paths.bundled {
            DispatchQueue.global().async {
                let build = Run.bashUser("make -C \(sh(Paths.root))/pam")
                DispatchQueue.main.async {
                    if build.code != 0 { finishSudo(String(format: L("set.msg.buildfail"), build.out)) }
                    else { proceedSudo(want) }
                }
            }
        } else {
            proceedSudo(want)
        }
    }

    private func proceedSudo(_ want: Bool) {
        switch HelperManager.shared.ensureRegistered() {
        case .needsApproval: finishSudo(L("set.msg.approve")); return
        case .failed(let e): finishSudo(String(format: L("set.msg.cancelled"), e)); return
        case .enabled: break
        }
        let onDone: (Bool, String) -> Void = { ok, msg in
            finishSudo(ok ? (want ? L("set.msg.sudo.on") : L("set.msg.sudo.off"))
                          : String(format: L("set.msg.cancelled"), msg))
        }
        if want { HelperManager.shared.enableSudo(onDone) }
        else    { HelperManager.shared.disableSudo(onDone) }
    }

    private func finishSudo(_ msg: String) {
        busy = false; note = msg; sudoActive = Status.sudoActive
    }

    private func sh(_ s: String) -> String { "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'" }
}

// Petit utilitaire : exécuter une closure quand un Binding change.
extension Binding {
    func onChange(_ action: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue },
                set: { newValue in wrappedValue = newValue; action() })
    }
}
