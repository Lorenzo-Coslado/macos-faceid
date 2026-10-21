// Native visual QA without camera access or changes to the enrolled face.
// Compile with Branding.swift, EnrollmentStream.swift and Onboarding.swift.
import AppKit
import SwiftUI

final class EnrollmentPreviewControls: NSObject {
    let controller = EnrollController()
    @objc func show(_ sender: NSMenuItem) {
        controller.reset()
        switch sender.tag {
        case 2:
            controller.phase = .scanning
            controller.hint = "move"
            controller.coverage = [1, 1, 1, 0, 0, 0, 0, 1]
            controller.sector = 3
            controller.count = 5
            controller.preview = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: "Preview fixture")
        case 3:
            controller.phase = .betweenPasses
            controller.coverage = Array(repeating: 1, count: 8)
        case 4: controller.phase = .done
        case 5:
            controller.phase = .failed
            controller.message = L("err.enroll-timeout")
        default: break
        }
    }
}

@main struct EnrollmentPreview {
    static var panel: NSPanel?
    static let controls = EnrollmentPreviewControls()
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let root = NSMenuItem()
        let previews = NSMenu(title: "Preview")
        for index in 1...5 {
            let item = NSMenuItem(title: "State \(index)", action: #selector(EnrollmentPreviewControls.show(_:)), keyEquivalent: String(index))
            item.target = controls; item.tag = index
            previews.addItem(item)
        }
        root.submenu = previews; menu.addItem(root); app.mainMenu = menu
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let geometry = EnrollmentIslandGeometry(screen: screen)
        let win = EnrollmentPanel(contentRect: geometry.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = true
        win.level = .statusBar; win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.delegate = controls
        let view = OnboardingView(c: controls.controller, attachment: geometry.attachment,
                                  onCancel: { app.terminate(nil) }, onFinish: { app.terminate(nil) })
        win.contentView = NSHostingView(rootView: view)
        panel = win
        win.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

extension EnrollmentPreviewControls: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
