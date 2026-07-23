// auth-modal — panneau de choix d'authentification, style alerte macOS moderne.
//
//   auth-modal [--timeout N]
//
// Affiche : icône Face ID, titre, sous-titre, 3 boutons empilés.
// Écrit sur stdout le choix : "face" | "touch" | "password", puis exit 0.
// Timeout (défaut 90 s), fermeture ou Échap -> "password".
//
// Compilation :
//   swiftc -O -o auth-modal auth-modal.swift -framework AppKit
import AppKit

// ---- localisation (anglais par défaut, français si le système est en FR) ----
let isFR = (Locale.preferredLanguages.first ?? "en").hasPrefix("fr")
func T(_ en: String, _ fr: String) -> String { isFR ? fr : en }

// ---- arguments ----
var timeoutS: Double = 90
if let i = CommandLine.arguments.firstIndex(of: "--timeout"),
   i + 1 < CommandLine.arguments.count,
   let v = Double(CommandLine.arguments[i + 1]) {
    timeoutS = v
}

// Icône : ../assets/faceid-icon.png relatif à l'exécutable.
let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath().deletingLastPathComponent()
let iconPath = exeDir.deletingLastPathComponent()
    .appendingPathComponent("assets/faceid-icon.png").path

func finish(_ choice: String) -> Never {
    print(choice)
    exit(0)
}

final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: PanelWindow!

    @objc func chooseFace() { finish("face") }
    @objc func chooseTouch() { finish("touch") }
    @objc func choosePassword() { finish("password") }

    func makeButton(_ title: String, _ action: Selector,
                    isDefault: Bool = false, key: String = "") -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.font = .systemFont(ofSize: 13, weight: isDefault ? .semibold : .regular)
        if isDefault {
            b.keyEquivalent = "\r"           // Entrée -> bouton accent système
            if #available(macOS 10.14, *) { b.bezelColor = .controlAccentColor }
        } else if !key.isEmpty {
            b.keyEquivalent = key
        }
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 236).isActive = true
        return b
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let w = PanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.isMovableByWindowBackground = true
        w.hasShadow = true
        window = w

        // Fond « verre » à la Apple, coins très arrondis.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        effect.translatesAutoresizingMaskIntoConstraints = false

        // Icône
        let icon = NSImageView()
        if let img = NSImage(contentsOfFile: iconPath) {
            icon.image = img
        } else {
            icon.image = NSImage(named: NSImage.lockLockedTemplateName)
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        // Titre + sous-titre
        let title = NSTextField(labelWithString: T("Authentication required", "Authentification requise"))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: T("sudo wants to verify your identity", "sudo souhaite vérifier ton identité"))
        subtitle.font = .systemFont(ofSize: 11.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        // Boutons (principal en bas de pile visuelle inversée : Face ID en haut)
        let faceBtn = makeButton(T("Use Face ID", "Utiliser Face ID"), #selector(chooseFace), isDefault: true)
        let touchBtn = makeButton(T("Use fingerprint", "Utiliser l'empreinte"), #selector(chooseTouch))
        let pwdBtn = makeButton(T("Enter password", "Saisir le mot de passe"), #selector(choosePassword),
                                key: "\u{1b}")   // Échap

        let stack = NSStackView(views: [icon, title, subtitle, faceBtn, touchBtn, pwdBtn])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(18, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -22),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -22),
        ])

        w.contentView = effect
        effect.layoutSubtreeIfNeeded()
        w.setContentSize(effect.fittingSize)
        w.center()

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutS) {
            finish("password")
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // pas d'icône Dock
let delegate = Delegate()
app.delegate = delegate
app.run()
