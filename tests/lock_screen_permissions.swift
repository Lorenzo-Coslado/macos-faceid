import Foundation

// Simulate macOS granting event posting while the AX query still reports false.
private var axTrusted = false
private var postTrusted = false
private var requests = 0
func AXIsProcessTrusted() -> Bool { axTrusted }
func CGPreflightPostEventAccess() -> Bool { postTrusted }
func CGRequestPostEventAccess() -> Bool { requests += 1; return false }

final class Settings {
    static let shared = Settings()
    var screenUnlockEnabled = false
    var env: [String: String] { [:] }
}
enum Status { static var enrolled: Bool { false } }
enum LoginPasswordStore {
    static var isConfigured: Bool { false }
    static func load() -> Data? { nil }
}
enum Run {
    static func faceid(_ args: [String], env: [String: String]) -> (code: Int32, out: String) {
        (1, "FAIL")
    }
}

@main
struct PermissionTests {
    static func main() {
        precondition(!LockScreenAccessibility.isTrusted, "No permission must remain blocked")
        _ = LockScreenAccessibility.request()
        _ = LockScreenAccessibility.request()
        precondition(requests == 1, "Repeated Configure clicks must not spam system consent prompts")
        postTrusted = true
        precondition(LockScreenAccessibility.request())
        precondition(requests == 1)
        precondition(LockScreenAccessibility.isTrusted,
                     "Mugshot still blocks unlock although event posting was granted")
        postTrusted = false
        axTrusted = true
        precondition(LockScreenAccessibility.isTrusted,
                     "A real Accessibility grant must be accepted even when PostEvent reports false")
        var session: [String: Any] = ["CGSSessionScreenIsLocked": true,
                                     "kCGSSessionOnConsoleKey": true,
                                     "kCGSSessionLoginDoneKey": true,
                                     "kCGSSessionUserIDKey": 501]
        precondition(LockScreenDestination.sessionIsEligible(session, userID: 501))
        precondition(!LockScreenDestination.sessionIsEligible(session, userID: 502), "Never target another user's session")
        session["kCGSSessionOnConsoleKey"] = false
        precondition(!LockScreenDestination.sessionIsEligible(session, userID: 501), "Fast user switching must cancel delivery")
        session["kCGSSessionOnConsoleKey"] = true
        session["kCGSSessionLoginDoneKey"] = false
        precondition(!LockScreenDestination.sessionIsEligible(session, userID: 501), "First login must stay unsupported")
        var destination: pid_t? = 614
        var posts = 0
        let secret = Data("fixture-password".utf8)
        let delivered = LockScreenPasswordDelivery.deliver(load: { secret }, target: { destination }) { data, pid in
            precondition(pid == 614 && data == secret); posts += 1
        }
        precondition(delivered && posts == 1)
        precondition(!LockScreenPasswordDelivery.deliver(load: { destination = nil; return secret },
                                                       target: { destination }, post: { _, _ in posts += 1 }),
                     "Unlock or revoked consent during Keychain lookup must cancel delivery")
        destination = 614
        precondition(!LockScreenPasswordDelivery.deliver(load: { destination = 615; return secret },
                                                       target: { destination }, post: { _, _ in posts += 1 }),
                     "A changed destination must cancel delivery")
        precondition(posts == 1, "Rejected deliveries must never emit keyboard events")
        print("OK: Accessibility or keyboard posting grant is accepted; prompts are deduplicated")
        print("OK: password targets loginwindow; session changes during Keychain lookup cancel delivery")
    }
}
