// HelperManager — côté app : enregistre le daemon root (SMAppService) et lui parle
// en XPC pour activer/désactiver sudo. Remplace l'ancien Run.admin (osascript), cassé
// sur macOS 26 (authtrampoline casse l'attribution → écriture /etc/pam.d refusée).
import Foundation
import ServiceManagement
import AppKit

final class HelperManager {
    static let shared = HelperManager()
    private let plistName = "com.lorenzo.Mugshot.Helper.plist"
    private let teamID = "RQUR2C3YDZ"
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
        DispatchQueue.main.async { SMAppService.openSystemSettingsLoginItems() }
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
                return .failed(error.localizedDescription)
            }
        }
    }

    func unregister() { try? service.unregister() }

    // MARK: XPC

    private func newConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: kMugshotHelperMachService, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: MugshotHelperProtocol.self)
        // N'accepte que le daemon signé par notre équipe Developer ID.
        try? c.setCodeSigningRequirement("anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\"")
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
}
