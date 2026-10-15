// Stockage du mot de passe utilisé uniquement après une reconnaissance faciale
// réussie sur l'écran verrouillé. Le secret reste dans le Data Protection Keychain
// de cette machine et n'est jamais envoyé au daemon Python.
import Foundation
import Security
import OpenDirectory
import LocalAuthentication

enum LoginPasswordStore {
    private static let service = "com.lorenzo.Mugshot.lock-screen"
    private static var account: String { NSUserName() }

    enum StoreError: LocalizedError {
        case empty
        case invalidPassword
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .empty:
                return L("lock.password.empty")
            case .invalidPassword:
                return L("lock.password.invalid")
            case .keychain(let status):
                return SecCopyErrorMessageString(status, nil) as String?
                    ?? "Keychain error \(status)"
            }
        }
    }

    static var isConfigured: Bool {
        // Metadata alone can succeed after a signing-identity migration even when
        // the old item's ACL prevents retrieval at the lock screen.
        hasReadablePassword(in: dataProtectionQuery) || hasReadablePassword(in: legacyQuery)
    }

    static func hasReadablePassword(in query: [String: Any]) -> Bool {
        guard var data = load(from: query) else { return false }
        data.resetBytes(in: 0..<data.count)
        return true
    }

    static func verifyAndSave(_ password: String) throws {
        guard !password.isEmpty else { throw StoreError.empty }

        do {
            let node = try ODNode(session: ODSession.default(), type: UInt32(kODNodeTypeLocalNodes))
            let record = try node.record(
                withRecordType: kODRecordTypeUsers,
                name: account,
                attributes: nil
            )
            try record.verifyPassword(password)
        } catch {
            throw StoreError.invalidPassword
        }

        let data = Data(password.utf8)
        delete()
        var query = dataProtectionQuery
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data
        var status = SecItemAdd(query as CFDictionary, nil)

        // Une signature ad hoc n'a pas d'application-identifier Apple et le Data
        // Protection Keychain renvoie errSecMissingEntitlement. Le Keychain macOS
        // classique reste local à ce compte et accessible pendant le verrouillage ;
        // c'est le repli nécessaire aux builds de développement.
        if status == errSecMissingEntitlement {
            var fallback = legacyQuery
            fallback[kSecValueData as String] = data
            status = SecItemAdd(fallback as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    static func load() -> Data? {
        load(from: dataProtectionQuery) ?? load(from: legacyQuery)
    }

    private static func load(from base: [String: Any]) -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Never put a Keychain authorization dialog behind loginwindow, nor spam
        // prompts while checking readiness. An inaccessible item needs setup again.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    @discardableResult
    static func delete() -> Bool {
        let protectedStatus = SecItemDelete(dataProtectionQuery as CFDictionary)
        let legacyStatus = SecItemDelete(legacyQuery as CFDictionary)
        return [protectedStatus, legacyStatus].allSatisfy {
            $0 == errSecSuccess || $0 == errSecItemNotFound || $0 == errSecMissingEntitlement
        }
    }

    private static var legacyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static var dataProtectionQuery: [String: Any] {
        var query = legacyQuery
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }
}
