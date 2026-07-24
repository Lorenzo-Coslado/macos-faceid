// MugshotHelper — daemon root (LaunchDaemon via SMAppService). Reçoit en XPC les
// ordres enable/disable sudo et exécute les scripts privilégiés en root, avec une
// vraie attribution système (pas d'authtrampoline) → l'écriture /etc/pam.d passe.
// N'accepte QUE les connexions d'un client signé comme nous (CodesignCheck).
import Foundation

/// Chemin de l'exécutable du helper, fiable même lancé par launchd.
func helperExecutablePath() -> String {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buf = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buf, &size) == 0 else { return CommandLine.arguments[0] }
    return String(cString: buf)
}

/// <App>.app/Contents/Resources déduit depuis .../Contents/MacOS/MugshotHelper.
func resourcesDir() -> URL {
    URL(fileURLWithPath: helperExecutablePath())
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()   // Contents/MacOS
        .deletingLastPathComponent()   // Contents
        .appendingPathComponent("Resources")
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate, MugshotHelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        guard (try? CodesignCheck.codeSigningMatches(pid: c.processIdentifier)) == true else {
            NSLog("MugshotHelper: connexion refusée (signature client invalide)")
            return false
        }
        c.exportedInterface = NSXPCInterface(with: MugshotHelperProtocol.self)
        c.exportedObject = self
        c.resume()
        return true
    }

    private func runScript(_ name: String, reply: @escaping (Bool, String) -> Void) {
        let script = resourcesDir().appendingPathComponent("scripts/\(name)").path
        guard FileManager.default.fileExists(atPath: script) else {
            reply(false, "script introuvable : \(script)"); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { reply(false, "\(error)"); return }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        reply(p.terminationStatus == 0, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func enableSudo(withReply reply: @escaping (Bool, String) -> Void) {
        runScript("pam-install-root.sh", reply: reply)
    }
    func disableSudo(withReply reply: @escaping (Bool, String) -> Void) {
        runScript("pam-uninstall-root.sh", reply: reply)
    }
    func version(withReply reply: @escaping (String) -> Void) {
        reply(kMugshotHelperVersion)
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: kMugshotHelperMachService)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
