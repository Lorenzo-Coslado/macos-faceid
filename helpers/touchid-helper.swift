// touchid-helper — déclenche Touch ID via LocalAuthentication.
//
//   touchid-helper --check     -> "AVAILABLE" (exit 0) ou "UNAVAILABLE:..." (exit 1)
//   touchid-helper "raison"    -> "OK" (exit 0) / "FAIL" (exit 1) / erreur (exit 2)
//
// Compilation :
//   swiftc -O -o touchid-helper touchid-helper.swift -framework LocalAuthentication
import Foundation
import LocalAuthentication

let ctx = LAContext()
// On gère le mot de passe via notre propre modal : masque le fallback natif.
ctx.localizedFallbackTitle = ""

var err: NSError?
let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics

if CommandLine.arguments.contains("--check") {
    let ok = ctx.canEvaluatePolicy(policy, error: &err)
    print(ok ? "AVAILABLE" : "UNAVAILABLE:\(err?.localizedDescription ?? "?")")
    exit(ok ? 0 : 1)
}

guard ctx.canEvaluatePolicy(policy, error: &err) else {
    FileHandle.standardError.write(
        "no-biometrics:\(err?.localizedDescription ?? "?")\n".data(using: .utf8)!)
    exit(2)
}

let reason = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("--")
    ? CommandLine.arguments[1]
    : "authentifier sudo"

let sem = DispatchSemaphore(value: 0)
var success = false
ctx.evaluatePolicy(policy, localizedReason: reason) { ok, _ in
    success = ok
    sem.signal()
}
sem.wait()

print(success ? "OK" : "FAIL")
exit(success ? 0 : 1)
