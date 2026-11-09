import Foundation
import Security

func L(_ key: String) -> String { key }

@main
struct KeychainReadinessTest {
    static func main() {
        // Dedicated random fixture: never query the user's real login-password item.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.lorenzo.Mugshot.test." + UUID().uuidString,
            kSecAttrAccount as String: "fixture",
        ]
        precondition(!LoginPasswordStore.hasReadablePassword(in: query))
        var add = query
        add[kSecValueData as String] = Data("test-fixture-only".utf8)
        precondition(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
        defer { SecItemDelete(query as CFDictionary) }
        precondition(LoginPasswordStore.hasReadablePassword(in: query),
                     "Noninteractive read must work for a readable legacy item")
        print("OK: readiness checks real readable data without authentication UI")
    }
}
