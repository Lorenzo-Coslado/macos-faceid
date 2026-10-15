// Déverrouillage de session à la manière de Sapphire : Mugshot reconnaît le visage
// dans la session utilisateur, puis saisit le mot de passe dans loginwindow au moyen
// d'événements clavier HID. Ce n'est pas une intégration au Face ID système.
import AppKit
import ApplicationServices
import Foundation
import Security
import Darwin

@_silgen_name("CGSessionCopyCurrentDictionary")
private func CGSessionCopyCurrentDictionary() -> CFDictionary?

enum LockScreenDestination {
    static func sessionIsEligible(_ values: [String: Any], userID: uid_t = getuid()) -> Bool {
        values["CGSSessionScreenIsLocked"] as? Bool == true
            && values["kCGSSessionOnConsoleKey"] as? Bool == true
            && values["kCGSSessionLoginDoneKey"] as? Bool == true
            && (values["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == userID
    }

    static var sessionIsEligible: Bool {
        guard let values = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return sessionIsEligible(values)
    }

    static func current() -> pid_t? {
        guard sessionIsEligible else { return nil }
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow")
            .filter { !$0.isTerminated && $0.executableURL?.path == "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow" }
        guard candidates.count == 1, let application = candidates.first else { return nil }
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple and identifier \"com.apple.loginwindow\"" as CFString,
                                             [], &requirement) == errSecSuccess,
              let requirement,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: application.processIdentifier] as CFDictionary,
                                            [], &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }
        return application.processIdentifier
    }
}

/// Re-check after Keychain retrieval: consent, session or target may have changed
/// while the secret was being read. The sender receives an explicit process ID.
enum LockScreenPasswordDelivery {
    @discardableResult
    static func deliver(load: () -> Data?, target: () -> pid_t?, post: (Data, pid_t) -> Void) -> Bool {
        guard let destination = target(), var data = load() else { return false }
        defer { data.resetBytes(in: 0..<data.count) }
        guard target() == destination else { return false }
        post(data, destination)
        return true
    }
}

enum LockScreenAccessibility {
    private static var didRequest = false
    // macOS can report AX=true while PostEvent=false for a valid Accessibility
    // grant. Either positive authorization is sufficient; two negatives block.
    static var isTrusted: Bool { AXIsProcessTrusted() || CGPreflightPostEventAccess() }

    @discardableResult
    static func request() -> Bool {
        if isTrusted { return true }
        // A rejected/stale TCC entry must not cause a fresh system alert on every
        // Configure click. Polling uses preflight only; one request per process.
        guard !didRequest else { return false }
        didRequest = true
        return CGRequestPostEventAccess()
    }

    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static var diagnostic: String {
        "Accessibility AX=\(AXIsProcessTrusted()); keyboard posting=\(CGPreflightPostEventAccess()); accepted=\(isTrusted); app=\(Bundle.main.bundleURL.path)"
    }
}

final class LockScreenUnlockCoordinator {
    private var generation: UInt64 = 0
    private var isLocked = false
    private var isAttempting = false

    func start() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(receivedScreenLocked),
            name: .init("com.apple.screenIsLocked"),
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(receivedScreenUnlocked),
            name: .init("com.apple.screenIsUnlocked"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(receivedWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        generation &+= 1
        isAttempting = false
    }

    @objc private func receivedScreenLocked() {
        DispatchQueue.main.async {
            self.isLocked = true
            self.generation &+= 1
            self.scheduleAttempt(generation: self.generation, delay: 0.15)
        }
    }

    @objc private func receivedScreenUnlocked() {
        DispatchQueue.main.async {
            self.isLocked = false
            self.generation &+= 1
            self.isAttempting = false
        }
    }

    @objc private func receivedWake() {
        DispatchQueue.main.async {
            guard self.isLocked, !self.isAttempting else { return }
            self.generation &+= 1
            self.isAttempting = false
            self.scheduleAttempt(generation: self.generation, delay: 0.35)
        }
    }

    private func scheduleAttempt(generation expected: UInt64, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.generation == expected else { return }
            self.attemptUnlock(generation: expected)
        }
    }

    private func attemptUnlock(generation expected: UInt64) {
        guard Settings.shared.screenUnlockEnabled,
              Status.enrolled,
              LoginPasswordStore.isConfigured,
              LockScreenAccessibility.isTrusted,
              isLocked,
              !isAttempting,
              Self.isScreenActuallyLocked()
        else { return }

        isAttempting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Run.faceid(["verify", "--lock"], env: Settings.shared.env)
            DispatchQueue.main.async {
                guard self.generation == expected, self.isLocked else {
                    self.isAttempting = false
                    return
                }
                guard result.code == 0,
                      result.out.split(whereSeparator: \.isWhitespace).contains("OK"),
                      Self.isScreenActuallyLocked()
                else {
                    self.isAttempting = false
                    return
                }
                self.injectStoredPassword(generation: expected)
            }
        }
    }

    private func injectStoredPassword(generation expected: UInt64) {
        wakeDisplay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            defer { self.isAttempting = false }
            LockScreenPasswordDelivery.deliver(load: LoginPasswordStore.load, target: {
                guard self.generation == expected, self.isLocked,
                      Settings.shared.screenUnlockEnabled, Status.enrolled,
                      LockScreenAccessibility.isTrusted else { return nil }
                return LockScreenDestination.current()
            }, post: Self.postPassword)
        }
    }

    private func wakeDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-u", "-t", "1"]
        try? process.run()
    }

    private static func postPassword(_ data: Data, to destination: pid_t) {
        guard let password = String(data: data, encoding: .utf8),
              let source = CGEventSource(stateID: .hidSystemState)
        else { return }

        var characters = Array(password.utf16)
        defer {
            for index in characters.indices { characters[index] = 0 }
        }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(
                stringLength: characters.count,
                unicodeString: &characters
            )
            down.postToPid(destination)
        }
        CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)?
            .postToPid(destination)
        CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)?
            .postToPid(destination)
        CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)?
            .postToPid(destination)
    }

    private static func isScreenActuallyLocked() -> Bool {
        LockScreenDestination.sessionIsEligible
    }
}
