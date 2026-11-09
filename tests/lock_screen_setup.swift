import SwiftUI

func L(_ key: String) -> String { key }
enum Brand { static let green = Color.green }
enum AppController { static var suppressQuitWarning = false }
enum LockScreenAccessibility {
    static var isTrusted: Bool { false }
    static func request() -> Bool { false }
    static func openSettings() {}
}
final class Settings {
    static let shared = Settings()
    var screenUnlockEnabled = false
}
enum LoginPasswordStore {
    static var isConfigured: Bool { false }
    static func verifyAndSave(_ password: String) throws {}
}

@main
struct SetupTests {
    @MainActor static func main() async {
        var camera = true
        var posting = false
        var passwordSaved = false
        var enabled = false
        var pending = false
        var prompts = 0
        var saves = 0
        var rejectPassword = false
        let services = LockScreenSetupFlow.Services(
            cameraGranted: { camera }, requestCamera: { $0(camera) },
            canPostEvents: { posting }, requestEvents: { prompts += 1 },
            passwordConfigured: { passwordSaved },
            savePassword: { _ in
                saves += 1
                if rejectPassword { throw NSError(domain: "invalid-password", code: 1) }
                passwordSaved = true
            },
            enable: { enabled = true }, setPending: { pending = $0 }
        )
        let flow = LockScreenSetupFlow(services: services, automaticallyPoll: false)
        flow.start()
        precondition(flow.step == .accessibility && pending && !enabled)
        flow.refresh(); flow.refresh()
        precondition(prompts == 1, "Polling must not reopen System Settings every second")
        posting = true
        flow.refresh()
        precondition(flow.step == .password && !enabled, "Grant must advance without a second Configure click")
        rejectPassword = true
        flow.save("dummy-test-password")
        try? await Task.sleep(nanoseconds: 100_000_000)
        precondition(!enabled && pending && !flow.message.isEmpty && !flow.saving)
        let errorMessage = flow.message
        flow.refresh()
        precondition(flow.message == errorMessage, "Polling must preserve the password error")
        rejectPassword = false
        flow.save("dummy-test-password")
        try? await Task.sleep(nanoseconds: 100_000_000)
        precondition(flow.step == .done && enabled && !pending && saves == 2)

        enabled = false; posting = false
        let repair = LockScreenSetupFlow(services: services, automaticallyPoll: false)
        repair.start()
        precondition(repair.step == .accessibility)
        repair.stop()
        posting = true
        repair.start()
        precondition(repair.step == .done && enabled, "Restart must preserve the saved password and resume")

        enabled = false; posting = false
        let cancelled = LockScreenSetupFlow(services: services, automaticallyPoll: false)
        cancelled.start(); cancelled.cancel()
        posting = true; cancelled.refresh()
        precondition(!pending && !enabled, "Late permission approval cannot enable a cancelled setup")

        passwordSaved = false
        let revoked = LockScreenSetupFlow(services: services, automaticallyPoll: false)
        revoked.start()
        posting = false
        revoked.save("dummy-test-password")
        precondition(revoked.step == .accessibility && saves == 2 && !enabled)
        revoked.cancel()

        camera = false
        let denied = LockScreenSetupFlow(services: services, automaticallyPoll: false)
        denied.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        precondition(denied.step == .camera && !enabled)
        camera = true; posting = true
        denied.refresh()
        precondition(denied.step == .password, "Camera consent granted in Settings must also resume")
        denied.cancel()
        print("OK: approval, password failure/retry, restart, cancellation and revoked consent")
    }
}
