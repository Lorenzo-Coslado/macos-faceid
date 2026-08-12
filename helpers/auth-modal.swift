// auth-modal — panneau de choix d'authentification, style alerte macOS moderne.
//
//   auth-modal [--timeout N] [--title T] [--subtitle S]
//              [--face F] [--touch U] [--password P]
//
// Affiche : icône Face ID, titre, sous-titre, 3 boutons empilés.
// Écrit sur stdout le choix : "face" | "touch" | "password", puis exit 0.
// Timeout (défaut 90 s), fermeture ou Échap -> "password".
//
// Les libellés viennent du daemon, qui les lit dans i18n/engine.json : ce binaire n'a
// pas de bundle, donc pas de .lproj, et il ne couvrait que l'anglais et le français
// alors que l'app est traduite en onze langues.
//
// Compilation :
//   swiftc -O -o auth-modal auth-modal.swift -framework AppKit
import AppKit

// ---- arguments ----
func arg(_ name: String, _ fallback: String) -> String {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return fallback }
    return a[i + 1]
}

let timeoutS = Double(arg("--timeout", "90")) ?? 90
let titleText = arg("--title", "Authentication required")
let subtitleText = arg("--subtitle", "sudo wants to verify your identity")
let faceText = arg("--face", "Use Face ID")
let touchText = arg("--touch", "Use fingerprint")
let passwordText = arg("--password", "Enter password")

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
        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = .systemFont(ofSize: 11.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        // Boutons (principal en bas de pile visuelle inversée : Face ID en haut)
        let faceBtn = makeButton(faceText, #selector(chooseFace), isDefault: true)
        let touchBtn = makeButton(touchText, #selector(chooseTouch))
        let pwdBtn = makeButton(passwordText, #selector(choosePassword),
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
