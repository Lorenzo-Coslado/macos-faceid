//  CodesignCheck.swift — vérifie que deux process partagent la même identité de
//  signature (mêmes certificats). Utilisé par le daemon pour n'accepter que notre app.
//  Created by Erik Berglund (2018). Réutilisé tel quel.
import Foundation
import Security

let kSecCSDefaultFlags = 0

enum CodesignCheckError: Error {
    case message(String)
}

struct CodesignCheck {

    public static func codeSigningMatches(pid: pid_t) throws -> Bool {
        guard let ownCode = try secStaticCodeSelf(),
              let peerCode = try secStaticCode(forPID: pid),
              let ownInfo = try secCodeInfo(forStaticCode: ownCode),
              let peerInfo = try secCodeInfo(forStaticCode: peerCode) else { return false }

        let ownCertificates = certificates(from: ownInfo)
        let peerCertificates = certificates(from: peerInfo)

        // Une release Developer ID doit conserver exactement la même chaîne de
        // certificats des deux côtés. Un mélange signed/ad-hoc est toujours refusé.
        if !ownCertificates.isEmpty || !peerCertificates.isEmpty {
            return !ownCertificates.isEmpty && ownCertificates == peerCertificates
        }

        // Les builds locaux ad-hoc n'ont aucun certificat à comparer. On limite
        // alors le client au binaire principal attendu, dans le même bundle .app
        // que ce helper, après validation cryptographique des deux Mach-O ci-dessus.
        guard identifier(from: peerInfo) == "com.lorenzo.Mugshot",
              let ownExecutable = executableURL(from: ownInfo),
              let peerExecutable = executableURL(from: peerInfo),
              ownExecutable.lastPathComponent == "MugshotHelper",
              peerExecutable.lastPathComponent == "Mugshot",
              let ownApp = containingAppURL(for: ownExecutable),
              let peerApp = containingAppURL(for: peerExecutable) else { return false }
        return ownApp == peerApp
    }

    public static func codeSigningCertificatesForSelf() throws -> [SecCertificate] {
        guard let secStaticCode = try secStaticCodeSelf() else { return [] }
        return try codeSigningCertificates(forStaticCode: secStaticCode)
    }

    public static func codeSigningCertificates(forPID pid: pid_t) throws -> [SecCertificate] {
        guard let secStaticCode = try secStaticCode(forPID: pid) else { return [] }
        return try codeSigningCertificates(forStaticCode: secStaticCode)
    }

    private static func executeSecFunction(_ secFunction: () -> (OSStatus)) throws {
        let osStatus = secFunction()
        guard osStatus == errSecSuccess else {
            throw CodesignCheckError.message(String(describing: SecCopyErrorMessageString(osStatus, nil)))
        }
    }

    private static func secStaticCodeSelf() throws -> SecStaticCode? {
        var secCodeSelf: SecCode?
        try executeSecFunction { SecCodeCopySelf(SecCSFlags(rawValue: 0), &secCodeSelf) }
        guard let secCode = secCodeSelf else {
            throw CodesignCheckError.message("SecCode returned empty from SecCodeCopySelf")
        }
        return try secStaticCode(forSecCode: secCode)
    }

    private static func secStaticCode(forPID pid: pid_t) throws -> SecStaticCode? {
        var secCodePID: SecCode?
        try executeSecFunction { SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &secCodePID) }
        guard let secCode = secCodePID else {
            throw CodesignCheckError.message("SecCode returned empty from SecCodeCopyGuestWithAttributes")
        }
        return try secStaticCode(forSecCode: secCode)
    }

    private static func secStaticCode(forSecCode secCode: SecCode) throws -> SecStaticCode? {
        var secStaticCodeCopy: SecStaticCode?
        try executeSecFunction { SecCodeCopyStaticCode(secCode, [], &secStaticCodeCopy) }
        guard let secStaticCode = secStaticCodeCopy else {
            throw CodesignCheckError.message("SecStaticCode returned empty from SecCodeCopyStaticCode")
        }
        return secStaticCode
    }

    private static func isValid(secStaticCode: SecStaticCode) throws {
        try executeSecFunction { SecStaticCodeCheckValidity(secStaticCode, SecCSFlags(rawValue: kSecCSDoNotValidateResources | kSecCSCheckNestedCode), nil) }
    }

    private static func secCodeInfo(forStaticCode secStaticCode: SecStaticCode) throws -> [String: Any]? {
        try isValid(secStaticCode: secStaticCode)
        var secCodeInfoCFDict: CFDictionary?
        try executeSecFunction { SecCodeCopySigningInformation(secStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &secCodeInfoCFDict) }
        guard let secCodeInfo = secCodeInfoCFDict as? [String: Any] else {
            throw CodesignCheckError.message("CFDictionary returned empty from SecCodeCopySigningInformation")
        }
        return secCodeInfo
    }

    private static func codeSigningCertificates(forStaticCode secStaticCode: SecStaticCode) throws -> [SecCertificate] {
        guard let secCodeInfo = try secCodeInfo(forStaticCode: secStaticCode) else { return [] }
        return certificates(from: secCodeInfo)
    }

    private static func certificates(from info: [String: Any]) -> [SecCertificate] {
        info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
    }

    private static func identifier(from info: [String: Any]) -> String? {
        info[kSecCodeInfoIdentifier as String] as? String
    }

    private static func executableURL(from info: [String: Any]) -> URL? {
        guard let url = info[kSecCodeInfoMainExecutable as String] as? URL else { return nil }
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func containingAppURL(for executable: URL) -> URL? {
        var candidate = executable.deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate.standardizedFileURL.resolvingSymlinksInPath()
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}
