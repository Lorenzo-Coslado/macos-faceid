// HelperManager — côté app : enregistre le daemon root (SMAppService) et lui parle
// en XPC pour activer/désactiver sudo. Remplace l'ancien Run.admin (osascript), cassé
// sur macOS 26 (authtrampoline casse l'attribution → écriture /etc/pam.d refusée).
import Foundation
import ServiceManagement
import AppKit
import Security

final class HelperManager {
    static let shared = HelperManager()
    private let plistName = "com.lorenzo.Mugshot.Helper.plist"
    private var service: SMAppService { SMAppService.daemon(plistName: plistName) }

    var isEnabled: Bool { service.status == .enabled }

    /// Chemin du binaire du daemon (à ajouter à l'Accès complet au disque sur macOS 26).
    var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MugshotHelper").path
    }

    /// Ouvre le volet Réglages › Confidentialité › Accès complet au disque.
    func openFullDiskAccess() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }

    enum Reg { case enabled, needsApproval, failed(String) }

    private func openApproval() {
        if Thread.isMainThread {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            DispatchQueue.main.async { SMAppService.openSystemSettingsLoginItems() }
        }
    }

    /// Enregistre le daemon si nécessaire. `.needsApproval` → l'utilisateur doit
    /// l'activer dans Réglages > Éléments d'ouverture (on ouvre la fenêtre).
    func ensureRegistered() -> Reg {
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            openApproval()
            return .needsApproval
        default:
            do {
                try service.register()
                switch service.status {
                case .enabled: return .enabled
                case .requiresApproval:
                    openApproval()
                    return .needsApproval
                default: return .failed("statut inattendu : \(service.status.rawValue)")
                }
            } catch {
                if service.status == .requiresApproval {
                    openApproval()
                    return .needsApproval
                }
                return .failed(error.localizedDescription)
            }
        }
    }

    func unregister() { try? service.unregister() }

    /// Réenregistre explicitement le daemon après remplacement d'un build local
    /// ad-hoc (son cdhash change et macOS invalide alors l'ancien enregistrement).
    func refreshRegistration() -> Reg {
        do {
            if service.status != .notRegistered {
                try service.unregister()
            }
            try service.register()
            switch service.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                openApproval()
                return .needsApproval
            default:
                return .failed("statut inattendu : \(service.status.rawValue)")
            }
        } catch {
            if service.status == .requiresApproval {
                openApproval()
                return .needsApproval
            }
            return .failed(error.localizedDescription)
        }
    }

    // MARK: XPC

    /// Construit une exigence adaptée à la signature réellement installée.
    /// - Developer ID : même Team ID que l'app.
    /// - build local ad-hoc : cdhash exact du helper embarqué.
    private func helperCodeSigningRequirement() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return nil }
        var selfStaticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &selfStaticCode) == errSecSuccess,
              let selfStaticCode else { return nil }

        var selfInfoRef: CFDictionary?
        guard SecCodeCopySigningInformation(selfStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &selfInfoRef) == errSecSuccess,
              let selfInfo = selfInfoRef as? [String: Any] else { return nil }

        if let teamID = selfInfo[kSecCodeInfoTeamIdentifier as String] as? String,
           !teamID.isEmpty {
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        }

        var helperCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: helperPath) as CFURL, [], &helperCode) == errSecSuccess,
              let helperCode else { return nil }
        var helperInfoRef: CFDictionary?
        guard SecCodeCopySigningInformation(helperCode, SecCSFlags(rawValue: kSecCSSigningInformation), &helperInfoRef) == errSecSuccess,
              let helperInfo = helperInfoRef as? [String: Any],
              let cdhash = helperInfo[kSecCodeInfoUnique as String] as? Data else { return nil }
        return "cdhash H\"\(cdhash.map { String(format: "%02x", $0) }.joined())\""
    }

    private func newConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: kMugshotHelperMachService, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: MugshotHelperProtocol.self)
        if let requirement = helperCodeSigningRequirement() {
            c.setCodeSigningRequirement(requirement)
        } else {
            NSLog("Mugshot: impossible de construire l'exigence de signature du helper; validation côté helper uniquement")
        }
        c.resume()
        return c
    }

    private func call(_ invoke: @escaping (MugshotHelperProtocol, @escaping (Bool, String) -> Void) -> Void,
                      _ done: @escaping (Bool, String) -> Void) {
        let c = newConnection()
        let proxy = c.remoteObjectProxyWithErrorHandler { err in
            DispatchQueue.main.async { done(false, "Connexion au helper : \(err.localizedDescription)") }
        } as? MugshotHelperProtocol
        guard let proxy else { done(false, "Proxy XPC indisponible."); return }
        invoke(proxy) { ok, msg in
            DispatchQueue.main.async { c.invalidate(); done(ok, msg) }
        }
    }

    /// Active sudo via le daemon root. `done` appelé sur le main thread.
    func enableSudo(_ done: @escaping (Bool, String) -> Void) {
        call({ $0.enableSudo(withReply: $1) }, done)
    }
    func disableSudo(_ done: @escaping (Bool, String) -> Void) {
        call({ $0.disableSudo(withReply: $1) }, done)
    }

    /// Le helper a-t-il le droit d'écrire dans /etc/pam.d ? Ne modifie rien.
    func checkAccess(_ done: @escaping (Bool, String) -> Void) {
        call({ $0.checkAccess(withReply: $1) }, done)
    }

    /// Teste uniquement le canal XPC; ne modifie pas la configuration PAM.
    func probe(_ done: @escaping (Bool, String) -> Void) {
        let c = newConnection()
        let proxy = c.remoteObjectProxyWithErrorHandler { err in
            DispatchQueue.main.async {
                c.invalidate()
                done(false, "Connexion au helper : \(err.localizedDescription)")
            }
        } as? MugshotHelperProtocol
        guard let proxy else {
            c.invalidate()
            done(false, "Proxy XPC indisponible.")
            return
        }
        proxy.version { version in
            DispatchQueue.main.async {
                c.invalidate()
                done(version == kMugshotHelperVersion,
                     version == kMugshotHelperVersion
                        ? "helper v\(version) joignable"
                        : "version helper incompatible : \(version)")
            }
        }
    }
}
