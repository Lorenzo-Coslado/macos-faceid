// faceid-hud — capsule flottante façon « Dynamic Island » pour le scan Face ID.
//
// Affiche en haut de l'écran une pilule noire :
//   - état SCAN    : glyphe Face ID vert qui pulse + ligne de balayage
//   - état SUCCESS : morph animé vers un checkmark vert (cercle + coche tracés)
//   - état FAIL    : croix rouge + petit shake
//
// Piloté par stdin (une commande par ligne) :
//   "SUCCESS" | "OK"  -> anime la validation puis se ferme
//   "FAIL"            -> anime l'échec puis se ferme
//   "QUIT" | EOF      -> ferme immédiatement
//
// Compilation :
//   swiftc -O -o faceid-hud faceid-hud.swift -framework AppKit
import AppKit
import QuartzCore

// ---------- couleurs ----------
let GREEN = NSColor(calibratedRed: 0.525, green: 0.910, blue: 0.541, alpha: 1) // #86E88A
let RED   = NSColor(calibratedRed: 1.0,   green: 0.353, blue: 0.322, alpha: 1) // #FF5A52
let PILL  = NSColor(calibratedWhite: 0.04, alpha: 1.0)

// ---------- géométrie ----------
let W: CGFloat = 216, H: CGFloat = 56
let ICON: CGFloat = 40, PAD: CGFloat = 8

let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath().deletingLastPathComponent()
let iconPath = exeDir.deletingLastPathComponent()
    .appendingPathComponent("assets/faceid-icon.png").path

final class HUD: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var root: CALayer!          // contenu (pour scale global)
    var iconBox: CALayer!       // conteneur icône (origine top-left)
    var faceLayer: CALayer!     // image Face ID
    var scanLine: CALayer!
    var circle: CAShapeLayer!   // cercle du checkmark / de l'échec
    var mark: CAShapeLayer!     // coche ou croix
    var label: CATextLayer!
    var done = false

    // ---------- fenêtre ----------
    func applicationDidFinishLaunching(_ n: Notification) {
        // visibleFrame exclut la barre de menu / l'encoche : la pilule pend juste
        // en dessous, centrée — effet « Dynamic Island ».
        let vis = NSScreen.main!.visibleFrame
        let x = vis.midX - W / 2
        let y = vis.maxY - H - 6
        window = NSWindow(contentRect: NSRect(x: x, y: y, width: W, height: H),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        // Niveau très élevé pour tenter de passer au-dessus de l'écran verrouillé
        // (macOS peut malgré tout l'occulter : l'écran de verrouillage est sécurisé).
        window.level = NSWindow.Level(rawValue:
            Int(CGShieldingWindowLevel()))
        window.ignoresMouseEvents = true
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        content.wantsLayer = true
        window.contentView = content

        buildLayers(in: content.layer!)
        window.orderFrontRegardless()

        appear()
        startScanning()
        listenStdin()

        // Filet : si personne ne pilote, on se ferme.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.quit()
        }
    }

    // ---------- construction des calques ----------
    func buildLayers(in host: CALayer) {
        root = CALayer()
        root.frame = host.bounds
        host.addSublayer(root)

        // pilule noire
        let pill = CALayer()
        pill.frame = root.bounds
        pill.backgroundColor = PILL.cgColor
        pill.cornerRadius = H / 2
        pill.borderWidth = 0.5
        pill.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        root.addSublayer(pill)

        // conteneur icône, origine en haut-gauche
        iconBox = CALayer()
        iconBox.frame = CGRect(x: PAD, y: (H - ICON) / 2, width: ICON, height: ICON)
        iconBox.isGeometryFlipped = true
        iconBox.masksToBounds = true
        iconBox.cornerRadius = 9
        root.addSublayer(iconBox)

        // image Face ID
        faceLayer = CALayer()
        faceLayer.frame = iconBox.bounds
        faceLayer.contentsGravity = .resizeAspect
        if let img = NSImage(contentsOfFile: iconPath) {
            faceLayer.contents = img
        }
        iconBox.addSublayer(faceLayer)

        // ligne de balayage (dégradé vert horizontal fin)
        let grad = CAGradientLayer()
        grad.frame = CGRect(x: 4, y: 0, width: ICON - 8, height: 10)
        grad.startPoint = CGPoint(x: 0, y: 0.5)
        grad.endPoint = CGPoint(x: 1, y: 0.5)
        grad.colors = [NSColor.clear.cgColor,
                       GREEN.withAlphaComponent(0.9).cgColor,
                       NSColor.clear.cgColor]
        grad.cornerRadius = 5
        scanLine = grad
        iconBox.addSublayer(scanLine)

        // cercle (checkmark / échec), caché au départ
        circle = CAShapeLayer()
        circle.frame = iconBox.bounds
        let inset: CGFloat = 3
        circle.path = CGPath(ellipseIn: iconBox.bounds.insetBy(dx: inset, dy: inset),
                             transform: nil)
        circle.fillColor = NSColor.clear.cgColor
        circle.strokeColor = GREEN.cgColor
        circle.lineWidth = 3.2
        circle.lineCap = .round
        circle.strokeEnd = 0
        circle.opacity = 0
        iconBox.addSublayer(circle)

        // marque (coche), caché au départ
        mark = CAShapeLayer()
        mark.frame = iconBox.bounds
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 12, y: 21))
        p.addLine(to: CGPoint(x: 18, y: 27))
        p.addLine(to: CGPoint(x: 29, y: 14))
        mark.path = p
        mark.fillColor = NSColor.clear.cgColor
        mark.strokeColor = GREEN.cgColor
        mark.lineWidth = 3.4
        mark.lineCap = .round
        mark.lineJoin = .round
        mark.strokeEnd = 0
        mark.opacity = 0
        iconBox.addSublayer(mark)

        // label
        label = CATextLayer()
        label.frame = CGRect(x: PAD + ICON + 10, y: 0, width: W - (PAD + ICON + 10) - 12, height: H)
        label.string = "Face ID…"
        label.fontSize = 14
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.foregroundColor = NSColor.white.cgColor
        label.alignmentMode = .left
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        label.truncationMode = .end
        // centrage vertical du texte
        label.frame.origin.y = (H - 20) / 2
        label.frame.size.height = 20
        root.addSublayer(label)
    }

    // ---------- animations ----------
    func appear() {
        let s = CASpringAnimation(keyPath: "transform.scale")
        s.fromValue = 0.55; s.toValue = 1.0
        s.damping = 12; s.stiffness = 180; s.mass = 0.9
        s.duration = s.settlingDuration
        root.add(s, forKey: "appear")
        let o = CABasicAnimation(keyPath: "opacity")
        o.fromValue = 0; o.toValue = 1; o.duration = 0.25
        root.add(o, forKey: "fade")
    }

    func startScanning() {
        let move = CABasicAnimation(keyPath: "position.y")
        move.fromValue = 6; move.toValue = ICON - 6
        move.duration = 1.1
        move.autoreverses = true
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLine.add(move, forKey: "scan")

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.7; pulse.toValue = 1.0
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        faceLayer.add(pulse, forKey: "pulse")
    }

    func stopScanning() {
        scanLine.removeAllAnimations()
        scanLine.opacity = 0
        faceLayer.removeAnimation(forKey: "pulse")
    }

    func succeed() {
        guard !done else { return }
        done = true
        stopScanning()
        label.string = "Déverrouillé"

        // face fade out
        fade(faceLayer, to: 0, dur: 0.2)
        circle.opacity = 1; mark.opacity = 1

        // tracé du cercle puis de la coche
        stroke(circle, dur: 0.32)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            self.stroke(self.mark, dur: 0.24)
        }
        bounce()
        // léger halo vert de la pilule
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { self.dismiss() }
    }

    func failed() {
        guard !done else { return }
        done = true
        stopScanning()
        label.string = "Échec"
        circle.strokeColor = RED.cgColor
        mark.strokeColor = RED.cgColor
        // marque = croix
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 14, y: 14)); p.addLine(to: CGPoint(x: 26, y: 26))
        p.move(to: CGPoint(x: 26, y: 14)); p.addLine(to: CGPoint(x: 14, y: 26))
        mark.path = p
        fade(faceLayer, to: 0, dur: 0.2)
        circle.opacity = 1; mark.opacity = 1
        stroke(circle, dur: 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.stroke(self.mark, dur: 0.2)
        }
        shake()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { self.dismiss() }
    }

    // ---------- primitives ----------
    func stroke(_ l: CAShapeLayer, dur: CFTimeInterval) {
        let a = CABasicAnimation(keyPath: "strokeEnd")
        a.fromValue = 0; a.toValue = 1; a.duration = dur
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        a.fillMode = .forwards; a.isRemovedOnCompletion = false
        l.strokeEnd = 1
        l.add(a, forKey: "stroke")
    }

    func fade(_ l: CALayer, to: Float, dur: CFTimeInterval) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.toValue = to; a.duration = dur
        a.fillMode = .forwards; a.isRemovedOnCompletion = false
        l.opacity = to
        l.add(a, forKey: "fade")
    }

    func bounce() {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1.0, 1.08, 1.0]
        a.keyTimes = [0, 0.4, 1]
        a.duration = 0.4
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        root.add(a, forKey: "bounce")
    }

    func shake() {
        let a = CAKeyframeAnimation(keyPath: "position.x")
        let x = root.position.x
        a.values = [x, x - 7, x + 7, x - 5, x + 5, x]
        a.duration = 0.4
        root.add(a, forKey: "shake")
    }

    func dismiss() {
        let o = CABasicAnimation(keyPath: "opacity")
        o.toValue = 0; o.duration = 0.28
        o.fillMode = .forwards; o.isRemovedOnCompletion = false
        let s = CABasicAnimation(keyPath: "transform.scale")
        s.toValue = 0.7; s.duration = 0.28
        s.fillMode = .forwards; s.isRemovedOnCompletion = false
        root.add(o, forKey: "out"); root.add(s, forKey: "outs")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.quit() }
    }

    func quit() { NSApp.terminate(nil) }

    // ---------- stdin ----------
    func listenStdin() {
        let fh = FileHandle.standardInput
        fh.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {           // EOF
                // Si l'anim finale est en cours, on la laisse se terminer
                // (dismiss() fermera). Sinon, fermeture immédiate.
                DispatchQueue.main.async { if !self.done { self.quit() } }
                h.readabilityHandler = nil
                return
            }
            let txt = (String(data: data, encoding: .utf8) ?? "").uppercased()
            DispatchQueue.main.async {
                if txt.contains("SUCCESS") || txt.contains("OK") { self.succeed() }
                else if txt.contains("FAIL") { self.failed() }
                else if txt.contains("QUIT") { self.quit() }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // pas d'icône Dock, pas de vol de focus
let hud = HUD()
app.delegate = hud
app.run()
