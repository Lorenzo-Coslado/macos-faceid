// Branding.swift — couleurs, logo, chemins, réglages persistants, exécution.
import SwiftUI
import AppKit

/// Texte localisé (Localizable.strings, repli anglais).
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Exécute une closure sur le thread principal (obligatoire pour AppKit /
/// NSAppleScript avec privilèges admin) et retourne son résultat.
func onMain<T>(_ work: @escaping () -> T) -> T {
    if Thread.isMainThread { return work() }
    return DispatchQueue.main.sync(execute: work)
}

enum Paths {
    // FaceIDProjectRoot est injecté au build (build-app.sh) selon l'emplacement
    // du clone. Le fallback n'est qu'un filet et n'est jamais utilisé en pratique.
    static let root = Bundle.main.infoDictionary?["FaceIDProjectRoot"] as? String
        ?? (NSHomeDirectory() as NSString).appendingPathComponent("Dev/macos-faceid")
    static var python: String { "\(root)/.venv/bin/python" }
    static func script(_ n: String) -> String { "\(root)/scripts/\(n)" }
    static var supportDir: String {
        NSString(string: "~/Library/Application Support/faceid").expandingTildeInPath
    }
}

enum Brand {
    static let green = Color(red: 0.525, green: 0.910, blue: 0.541)
    static let greenNS = NSColor(red: 0.525, green: 0.910, blue: 0.541, alpha: 1)
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.07)

    static func logo() -> NSImage? {
        if let p = Bundle.main.path(forResource: "faceid-icon", ofType: "png"),
           let i = NSImage(contentsOfFile: p) { return i }
        return NSApp.applicationIconImage
    }
}

/// Réglages persistés (UserDefaults) et poussés au daemon via l'environnement.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var threshold: Double { didSet { d.set(threshold, forKey: "faceid.threshold") } }
    @Published var modal: Bool { didSet { d.set(modal, forKey: "faceid.modal") } }
    @Published var hud: Bool { didSet { d.set(hud, forKey: "faceid.hud") } }

    private init() {
        threshold = d.object(forKey: "faceid.threshold") as? Double ?? 0.36
        modal = d.object(forKey: "faceid.modal") as? Bool ?? true
        hud = d.object(forKey: "faceid.hud") as? Bool ?? true
    }

    var env: [String: String] {
        ["FACEID_THRESHOLD": String(format: "%.2f", threshold),
         "FACEID_MODAL": modal ? "1" : "0",
         "FACEID_HUD": hud ? "1" : "0"]
    }
}

enum Status {
    static var enrolled: Bool {
        FileManager.default.fileExists(atPath: "\(Paths.supportDir)/embeddings.npy")
    }
    static var sudoActive: Bool {
        guard let s = try? String(contentsOfFile: "/etc/pam.d/sudo_local", encoding: .utf8)
        else { return false }
        return s.contains("pam_faceid")
    }
}

enum Run {
    /// Lance le Python du venv, bloquant, retourne (code, sortie).
    @discardableResult
    static func python(_ args: [String], env: [String: String] = [:]) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.python)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: Paths.root)
        var e = ProcessInfo.processInfo.environment
        e.merge(env) { _, n in n }
        p.environment = e
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Exécute une commande shell en root via le prompt admin natif de macOS.
    /// On lance `osascript` comme SOUS-PROCESSUS : le prompt SecurityAgent est
    /// géré hors de l'app (aucun NSAppleScript in-process, aucun risque de crash).
    static func admin(_ command: String) -> (ok: Bool, msg: String) {
        let esc = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(esc)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (false, "\(error)") }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // code 0 = OK ; sinon annulation (-128) ou erreur du script.
        return (p.terminationStatus == 0, out)
    }

    static func bashUser(_ command: String) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", command]
        p.currentDirectoryURL = URL(fileURLWithPath: Paths.root)
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
