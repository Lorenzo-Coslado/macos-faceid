// faceid-hud — « Fusion », extension animée de l'encoche pour le scan Face ID.
//
// Affiche en haut de l'écran une pilule noire :
//   - état SCAN    : glyphe Face ID vert qui pulse + ligne de balayage
//   - état SUCCESS : morph animé vers un checkmark vert (cercle + coche tracés)
//   - état FAIL    : cadenas ambre + petit shake de l'icône
//
// Piloté par stdin (une commande par ligne) :
//   "SUCCESS" | "OK"  -> anime la validation puis se ferme
//   "FAIL"            -> anime l'échec puis se ferme
//   "QUIT" | EOF      -> ferme immédiatement
//   --preview         -> démo native sans caméra ni authentification
//
// Compilation :
//   swiftc -O -o faceid-hud faceid-hud.swift -framework AppKit -framework QuartzCore
import AppKit
import QuartzCore
import Darwin

@_silgen_name("CGSessionCopyCurrentDictionary")
private func CGSessionCopyCurrentDictionary() -> CFDictionary?

private let requestedLockMode = CommandLine.arguments.contains("--lock")
private let sessionIsLocked: Bool = {
    guard let values = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return values["CGSSessionScreenIsLocked"] as? Bool ?? false
}()
private let lockScreenMode = requestedLockMode || sessionIsLocked

/// Place une fenêtre dans un Space SkyLight visible au-dessus de loginwindow.
/// Un simple `NSWindow.Level` ne suffit pas : le lock screen vit dans un Space séparé.
/// Cette API est privée et volontairement limitée au HUD éphémère du mode verrouillé.
final class LockScreenSpaceBridge {
    typealias MainConnection = @convention(c) () -> Int32
    typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let library: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: Int32
    private let addWindows: AddWindows

    init?() {
        guard let library = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ),
        let mainSymbol = dlsym(library, "SLSMainConnectionID"),
        let createSymbol = dlsym(library, "SLSSpaceCreate"),
        let levelSymbol = dlsym(library, "SLSSpaceSetAbsoluteLevel"),
        let showSymbol = dlsym(library, "SLSShowSpaces"),
        let addSymbol = dlsym(library, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }

        let main = unsafeBitCast(mainSymbol, to: MainConnection.self)
        let create = unsafeBitCast(createSymbol, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(levelSymbol, to: SpaceSetLevel.self)
        let show = unsafeBitCast(showSymbol, to: ShowSpaces.self)
        let add = unsafeBitCast(addSymbol, to: AddWindows.self)

        let connection = main()
        let space = create(connection, 1, 0)
        guard connection != 0, space != 0 else {
            dlclose(library)
            return nil
        }

        // 400 = Notification Center at screen lock, donc au-dessus du Space 300 de
        // loginwindow sans utiliser les niveaux boot/VoiceOver plus privilégiés.
        _ = setLevel(connection, space, 400)
        _ = show(connection, [space] as CFArray)

        self.library = library
        self.connection = connection
        self.space = space
        self.addWindows = add
    }

    func attach(_ window: NSWindow) {
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }

    deinit { dlclose(library) }
}

let isFR = (Locale.preferredLanguages.first ?? "en").hasPrefix("fr")
func T(_ en: String, _ fr: String) -> String { isFR ? fr : en }

// ---------- couleurs et proportions de la variante Fusion ----------
let GREEN = NSColor(calibratedRed: 0.525, green: 0.910, blue: 0.541, alpha: 1)
let AMBER = NSColor(calibratedRed: 0.898, green: 0.737, blue: 0.510, alpha: 1)
let ICON: CGFloat = 64
let previewMode = CommandLine.arguments.contains("--preview")

let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath().deletingLastPathComponent()
let iconPath = exeDir.deletingLastPathComponent()
    .appendingPathComponent("assets/faceid-icon.png").path

/// Les dimensions sont en points. L'encoche vient des zones sûres du véritable
/// écran, pas d'une largeur supposée ni de visibleFrame (qui dépend du Dock).
struct IslandGeometry {
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let notch: CGRect?

    init(frame: CGRect, visibleFrame: CGRect, safeTop: CGFloat,
         leftArea: CGRect?, rightArea: CGRect?) {
        screenFrame = frame
        self.visibleFrame = visibleFrame
        if safeTop > 0, let left = leftArea, let right = rightArea,
           right.minX > left.maxX {
            notch = CGRect(x: left.maxX, y: frame.maxY - safeTop,
                           width: right.minX - left.maxX, height: safeTop)
        } else {
            notch = nil
        }
    }

    init(screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame,
                  safeTop: screen.safeAreaInsets.top,
                  leftArea: screen.auxiliaryTopLeftArea,
                  rightArea: screen.auxiliaryTopRightArea)
    }

    var width: CGFloat { max(296, (notch?.width ?? 0) + 56) }
    var attachmentHeight: CGFloat { notch?.height ?? 0 }
    var canvasSize: CGSize { CGSize(width: width + 36, height: attachmentHeight + 126) }
    var centerX: CGFloat { canvasSize.width / 2 }
    var windowFrame: CGRect {
        let center = notch?.midX ?? visibleFrame.midX
        let top = notch != nil ? screenFrame.maxY : visibleFrame.maxY - 6
        return CGRect(x: center - canvasSize.width / 2,
                      y: top - canvasSize.height,
                      width: canvasSize.width, height: canvasSize.height)
    }
    var closedWidth: CGFloat { notch?.width ?? 112 }
    var closedBodyHeight: CGFloat { notch != nil ? 0 : 16 }

    /// Le fond rejoint le bord supérieur sur toute sa largeur. Seuls les coins
    /// inférieurs sont arrondis ; le contenu reste sous la caméra physique.
    /// La même suite de segments permet de passer de l'encoche à la pastille.
    func path(width bodyWidth: CGFloat, bodyHeight: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let left = centerX - bodyWidth / 2, right = centerX + bodyWidth / 2
        guard let notch else {
            path.addRoundedRect(in: CGRect(x: left, y: 0, width: bodyWidth,
                                           height: bodyHeight),
                                cornerWidth: min(30, bodyHeight / 2),
                                cornerHeight: min(30, bodyHeight / 2))
            return path
        }
        let bottom = notch.height + bodyHeight
        let radius = min(bottom / 2, 12 + 18 * min(1, max(0, bodyHeight / 96)))
        path.move(to: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: right, y: 0))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom),
                          control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius),
                          control: CGPoint(x: left, y: bottom))
        path.closeSubpath()
        return path
    }

    /// Core Animation sur macOS utilise ici un repère à origine basse. Le dessin
    /// reste décrit depuis l'encoche ; seuls ses points sont convertis.
    func layerPath(width: CGFloat, bodyHeight: CGFloat) -> CGPath {
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                     tx: 0, ty: canvasSize.height)
        return path(width: width, bodyHeight: bodyHeight).copy(using: &flip)!
    }
}

final class IslandWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Le clic et l'action VoiceOver annulent le scan sans réclamer le focus.
final class ClickView: NSView {
    var onClick: (() -> Void)?
    var containsPoint: ((CGPoint) -> Bool)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard containsPoint?(local) ?? true else { return nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

final class HUD: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var clickView: ClickView!
    var geometry: IslandGeometry!
    var root: CALayer!
    var pill: CAShapeLayer!
    var content: CALayer!
    var iconBox: CALayer!
    var faceLayer: CALayer!
    var scanLine: CALayer!
    var circle: CAShapeLayer!
    var mark: CAShapeLayer!
    var label: CATextLayer!
    var subtitle: CATextLayer!
    var statusDot: CALayer!
    var done = false
    var dismissing = false
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var commandBuffer = Data()
    var lockScreenSpace: LockScreenSpaceBridge?

    func applicationDidFinishLaunching(_ n: Notification) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { quit(); return }
        geometry = IslandGeometry(screen: screen)
        window = IslandWindow(contentRect: geometry.windowFrame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Mugshot Face ID"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.ignoresMouseEvents = false
        // L'ombre suit le contour animé, plutôt que le rectangle de la fenêtre.
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        clickView = ClickView(frame: CGRect(origin: .zero, size: geometry.canvasSize))
        clickView.onClick = { [weak self] in self?.cancel() }
        clickView.containsPoint = { [weak self] point in
            guard let self, !self.dismissing else { return false }
            return (self.pill.presentation()?.path ?? self.pill.path)?.contains(point) ?? false
        }
        clickView.setAccessibilityElement(true)
        clickView.setAccessibilityRole(.button)
        clickView.setAccessibilityLabel("Face ID")
        clickView.setAccessibilityHelp(T("Use password", "Utiliser le mot de passe"))
        clickView.wantsLayer = true
        window.contentView = clickView
        buildLayers(in: clickView.layer!, scale: screen.backingScaleFactor)
        window.orderFrontRegardless()

        if lockScreenMode && !previewMode {
            lockScreenSpace = LockScreenSpaceBridge()
            lockScreenSpace?.attach(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                guard let self, !self.dismissing else { return }
                self.lockScreenSpace?.attach(self.window)
                self.window.orderFrontRegardless()
            }
        }

        appear()
        startScanning()
        if previewMode {
            // Aperçu visuel uniquement : aucune caméra ni demande d'authentification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.succeed() }
        } else {
            listenStdin()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.quit() }
    }

    func buildLayers(in host: CALayer, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root = CALayer()
        root.frame = host.bounds
        root.contentsScale = scale
        host.addSublayer(root)

        pill = CAShapeLayer()
        pill.frame = root.bounds
        pill.fillColor = NSColor.black.cgColor
        pill.path = geometry.layerPath(width: geometry.closedWidth,
                                  bodyHeight: geometry.closedBodyHeight)
        pill.shadowColor = NSColor.black.cgColor
        pill.shadowOpacity = 0.24
        pill.shadowRadius = 10
        pill.shadowOffset = CGSize(width: 0, height: -7)
        pill.shadowPath = pill.path
        pill.contentsScale = scale
        pill.opacity = geometry.notch != nil ? 1 : 0
        root.addSublayer(pill)

        content = CALayer()
        content.frame = root.bounds
        content.opacity = 0
        root.addSublayer(content)
        let left = geometry.centerX - geometry.width / 2 + 24
        let top = geometry.canvasSize.height - geometry.attachmentHeight
        iconBox = CALayer()
        iconBox.frame = CGRect(x: left, y: top - 24 - ICON, width: ICON, height: ICON)
        content.addSublayer(iconBox)

        faceLayer = CALayer()
        faceLayer.frame = iconBox.bounds
        faceLayer.contentsGravity = .resizeAspect
        faceLayer.contentsScale = scale
        if let image = NSImage(contentsOfFile: iconPath) {
            faceLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else if let image = NSImage(systemSymbolName: "faceid", accessibilityDescription: "Face ID") {
            // Le glyphe du bundle reste prioritaire ; ce repli permet aussi de
            // prévisualiser un helper compilé seul dans un dossier temporaire.
            let tinted = NSImage(size: image.size)
            tinted.lockFocus()
            image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            GREEN.setFill()
            NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            faceLayer.contents = tinted.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        iconBox.addSublayer(faceLayer)

        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 7, y: 9, width: ICON - 14, height: 2)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.colors = [NSColor.clear.cgColor, GREEN.cgColor, NSColor.clear.cgColor]
        gradient.shadowColor = GREEN.cgColor
        gradient.shadowOpacity = 0.35
        gradient.shadowRadius = 4
        scanLine = gradient
        iconBox.addSublayer(scanLine)

        circle = CAShapeLayer()
        circle.frame = iconBox.bounds
        circle.path = CGPath(ellipseIn: iconBox.bounds.insetBy(dx: 8, dy: 8), transform: nil)
        circle.fillColor = NSColor.clear.cgColor
        circle.strokeColor = GREEN.cgColor
        circle.lineWidth = 2.8
        circle.lineCap = .round
        circle.strokeEnd = 0
        circle.opacity = 0
        iconBox.addSublayer(circle)

        mark = CAShapeLayer()
        mark.frame = iconBox.bounds
        mark.path = checkPath()
        mark.fillColor = NSColor.clear.cgColor
        mark.strokeColor = GREEN.cgColor
        mark.lineWidth = 3
        mark.lineCap = .round
        mark.lineJoin = .round
        mark.strokeEnd = 0
        mark.opacity = 0
        iconBox.addSublayer(mark)

        let textX = left + ICON + 20
        let textWidth = geometry.centerX + geometry.width / 2 - 24 - textX
        label = textLayer("Face ID", size: 18, weight: .semibold,
                          frame: CGRect(x: textX, y: top - 36 - 24, width: textWidth, height: 24),
                          color: .white, scale: scale)
        subtitle = textLayer(T("Looking for your face", "Recherche du visage"),
                             size: 11, weight: .regular,
                             frame: CGRect(x: textX + 9, y: top - 64 - 17,
                                           width: textWidth - 9, height: 17),
                             color: NSColor(white: 0.57, alpha: 1), scale: scale)
        statusDot = CALayer()
        statusDot.frame = CGRect(x: textX, y: top - 70 - 4, width: 4, height: 4)
        statusDot.backgroundColor = GREEN.cgColor
        statusDot.cornerRadius = 2
        content.addSublayer(statusDot)
        CATransaction.commit()
    }

    func textLayer(_ text: String, size: CGFloat, weight: NSFont.Weight,
                   frame: CGRect, color: NSColor, scale: CGFloat) -> CATextLayer {
        let layer = CATextLayer()
        layer.frame = frame
        layer.string = text
        layer.font = NSFont.systemFont(ofSize: size, weight: weight)
        layer.fontSize = size
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = .left
        layer.contentsScale = scale
        layer.truncationMode = .end
        content.addSublayer(layer)
        return layer
    }

    func checkPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: ICON * 27 / 88, y: ICON * 44 / 88))
        path.addLine(to: CGPoint(x: ICON * 39 / 88, y: ICON * 56 / 88))
        path.addLine(to: CGPoint(x: ICON * 62 / 88, y: ICON * 31 / 88))
        return iconCoordinates(path)
    }

    func lockPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 23, y: 29))
        path.addLine(to: CGPoint(x: 23, y: 22))
        path.addCurve(to: CGPoint(x: 41, y: 22),
                      control1: CGPoint(x: 23, y: 9), control2: CGPoint(x: 41, y: 9))
        path.addLine(to: CGPoint(x: 41, y: 29))
        path.move(to: CGPoint(x: 18, y: 29))
        path.addLine(to: CGPoint(x: 46, y: 29))
        path.addLine(to: CGPoint(x: 46, y: 51))
        path.addLine(to: CGPoint(x: 18, y: 51))
        path.closeSubpath()
        path.move(to: CGPoint(x: 32, y: 37))
        path.addLine(to: CGPoint(x: 32, y: 43))
        return iconCoordinates(path)
    }

    func iconCoordinates(_ path: CGPath) -> CGPath {
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: ICON)
        return path.copy(using: &flip)!
    }

    // ---------- animations ancrées à l'encoche ----------
    func appear() {
        morph(width: geometry.width, bodyHeight: 112, duration: 0.62)
        fade(pill, to: 1, duration: 0.18)
        let resting = content.position
        moveContent(to: resting, from: CGPoint(x: resting.x, y: resting.y + 9))
        fade(content, to: 1, duration: reduceMotion ? 0.12 : 0.24, delay: reduceMotion ? 0 : 0.12)
    }

    /// Un ressort presque amorti donne un déploiement souple. Le bord supérieur
    /// reste collé au haut de l'écran pendant tout le changement de contour.
    func morph(width: CGFloat, bodyHeight: CGFloat, duration: CFTimeInterval) {
        let from = pill.presentation()?.path ?? pill.path!
        let bounds = from.boundingBoxOfPath
        let initialWidth = bounds.width
        let initialHeight = bounds.height - geometry.attachmentHeight
        let target = geometry.layerPath(width: width, bodyHeight: bodyHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.path = target
        pill.shadowPath = target
        CATransaction.commit()
        guard !reduceMotion else { pill.removeAllAnimations(); return }

        let animation = CAKeyframeAnimation(keyPath: "path")
        var paths: [CGPath] = [from]
        let samples = 36
        for sample in 1...samples {
            let t = Double(sample) / Double(samples)
            let time = t * 0.62
            let spring = 1 - exp(-13.5 * time) * (cos(5.27 * time) + 13.5 / 5.27 * sin(5.27 * time))
            let progress = CGFloat(sample == samples ? 1 : spring)
            paths.append(geometry.layerPath(width: max(geometry.closedWidth,
                                                 initialWidth + (width - initialWidth) * progress),
                                       bodyHeight: max(geometry.closedBodyHeight,
                                                       initialHeight + (bodyHeight - initialHeight) * progress)))
        }
        animation.values = paths
        animation.duration = duration
        animation.calculationMode = .linear
        pill.add(animation, forKey: "morph")
        let shadow = animation.copy() as! CAKeyframeAnimation
        shadow.keyPath = "shadowPath"
        pill.add(shadow, forKey: "shadowMorph")
    }

    func moveContent(to target: CGPoint, from initial: CGPoint? = nil) {
        let from = initial ?? content.presentation()?.position ?? content.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.position = target
        CATransaction.commit()
        guard !reduceMotion else { content.removeAnimation(forKey: "move"); return }
        let animation = CASpringAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: from)
        animation.toValue = NSValue(point: target)
        animation.mass = 1
        animation.stiffness = 210
        animation.damping = 27
        animation.duration = animation.settlingDuration
        content.add(animation, forKey: "move")
    }

    func startScanning() {
        guard !reduceMotion else { scanLine.opacity = 0; return }
        let scan = CABasicAnimation(keyPath: "position.y")
        scan.fromValue = 10
        scan.toValue = ICON - 10
        scan.duration = 1.55
        scan.autoreverses = true
        scan.repeatCount = .infinity
        scan.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLine.add(scan, forKey: "scan")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.78
        pulse.toValue = 1
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        faceLayer.add(pulse, forKey: "pulse")
        statusDot.add(pulse, forKey: "pulse")
    }

    func stopScanning() {
        scanLine.removeAllAnimations()
        scanLine.opacity = 0
        faceLayer.removeAnimation(forKey: "pulse")
        statusDot.removeAnimation(forKey: "pulse")
    }

    func succeed() {
        guard !done else { return }
        done = true
        stopScanning()
        setText(T("Recognized", "Reconnu"), detail: T("Access granted", "Accès autorisé"), color: GREEN)
        fade(faceLayer, to: 0, duration: 0.18)
        fade(circle, to: 1, duration: 0.12)
        fade(mark, to: 1, duration: 0.12)
        stroke(circle, duration: 0.34)
        stroke(mark, duration: 0.25, delay: 0.16)
        compact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { [weak self] in self?.dismiss() }
    }

    func showPassword(_ detail: String) {
        stopScanning()
        setText(T("Password", "Mot de passe"), detail: detail, color: AMBER)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mark.path = lockPath()
        mark.strokeColor = AMBER.cgColor
        mark.lineWidth = 2.4
        CATransaction.commit()
        fade(faceLayer, to: 0, duration: 0.16)
        fade(mark, to: 1, duration: 0.12)
        stroke(mark, duration: 0.28)
    }

    func failed() {
        guard !done else { return }
        done = true
        showPassword(T("Face not recognized", "Visage non reconnu"))
        if !reduceMotion {
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [0, -3, 3, -2, 2, 0]
            shake.duration = 0.36
            iconBox.add(shake, forKey: "shake")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in self?.dismiss() }
    }

    func setText(_ title: String, detail: String, color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.string = title
        subtitle.string = detail
        subtitle.foregroundColor = color.withAlphaComponent(0.68).cgColor
        statusDot.backgroundColor = color.cgColor
        CATransaction.commit()
        clickView?.setAccessibilityValue("\(title). \(detail)")
    }

    func compact() {
        morph(width: max(geometry.closedWidth + 56, geometry.width - 28),
              bodyHeight: 90, duration: 0.46)
        let center = CGPoint(x: root.bounds.midX, y: root.bounds.midY + 11)
        moveContent(to: center)
    }

    func stroke(_ layer: CAShapeLayer, duration: CFTimeInterval, delay: CFTimeInterval = 0) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.strokeEnd = 1
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = reduceMotion ? 0.1 : duration
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + (reduceMotion ? 0 : delay)
        animation.fillMode = .backwards
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "stroke")
    }

    func fade(_ layer: CALayer, to value: Float, duration: CFTimeInterval,
              delay: CFTimeInterval = 0) {
        let initial = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = value
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = initial
        animation.toValue = value
        animation.duration = duration
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        animation.fillMode = .backwards
        layer.add(animation, forKey: "fade")
    }

    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        stopScanning()
        fade(content, to: 0, duration: reduceMotion ? 0.12 : 0.16)
        moveContent(to: CGPoint(x: root.bounds.midX, y: root.bounds.midY + 20))
        let duration: CFTimeInterval = reduceMotion ? 0.12 : 0.36
        morph(width: geometry.closedWidth, bodyHeight: geometry.closedBodyHeight, duration: duration)
        if geometry.notch == nil { fade(pill, to: 0, duration: duration) }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03) { [weak self] in self?.quit() }
    }

    func quit() {
        FileHandle.standardInput.readabilityHandler = nil
        NSApp.terminate(nil)
    }

    func cancel() {
        guard !done else { return }
        done = true
        FileHandle.standardOutput.write(Data("CANCEL\n".utf8))
        showPassword(T("Continue without Face ID", "Continuer sans Face ID"))
        dismiss()
    }

    // ---------- protocole du daemon (inchangé) ----------
    func command(_ line: String) {
        switch line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "SUCCESS", "OK": succeed()
        case "FAIL": failed()
        case "QUIT": quit()
        default: break
        }
    }

    func listenStdin() {
        let input = FileHandle.standardInput
        input.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.commandBuffer.append(data)
                while let newline = self.commandBuffer.firstIndex(of: 0x0a) {
                    let line = String(decoding: self.commandBuffer[..<newline], as: UTF8.self)
                    self.commandBuffer.removeSubrange(...newline)
                    self.command(line)
                }
                if data.isEmpty {
                    if !self.commandBuffer.isEmpty {
                        self.command(String(decoding: self.commandBuffer, as: UTF8.self))
                        self.commandBuffer.removeAll()
                    }
                    // Le daemon ferme stdin après SUCCESS/FAIL. L'animation finale
                    // doit se terminer avant la fermeture, même si EOF suit aussitôt.
                    if !self.done { self.quit() }
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let hud = HUD()
app.delegate = hud
app.run()
