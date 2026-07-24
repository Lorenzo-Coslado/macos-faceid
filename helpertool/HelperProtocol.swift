// Protocole XPC partagé entre l'app (client) et le daemon root (MugshotHelper).
// Compilé dans les deux cibles. Méthodes explicites (pas de runCommand générique)
// pour réduire la surface : le daemon ne fait QUE activer/désactiver sudo.
import Foundation

@objc(MugshotHelperProtocol)
public protocol MugshotHelperProtocol {
    /// Installe le module PAM + écrit /etc/pam.d/sudo_local (exécuté en root).
    func enableSudo(withReply reply: @escaping (Bool, String) -> Void)
    /// Retire l'intégration sudo (exécuté en root).
    func disableSudo(withReply reply: @escaping (Bool, String) -> Void)
    /// Version du helper, pour vérifier l'accord app/daemon.
    func version(withReply reply: @escaping (String) -> Void)
}

/// Nom du service mach + label du daemon (partagé app/helper).
public let kMugshotHelperMachService = "com.lorenzo.Mugshot.Helper"
public let kMugshotHelperVersion = "1"
