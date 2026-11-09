import Foundation
import Darwin

/// The old Python LaunchAgent and the app's engine used the same socket. Retire
/// that job before starting an engine, including after a DMG or Sparkle update.
enum LegacyAgentMigration {
    struct CommandResult {
        let status: Int32
        let output: String
    }

    static func retire(
        service: String = "gui/\(getuid())/com.lorenzo.faceid",
        run: ([String]) throws -> CommandResult = launchctl
    ) throws {
        // Persist this before stopping KeepAlive: bootout alone would leave the
        // conflicting Python engine free to return at the next login.
        let disabled = try run(["disable", service])
        guard disabled.status == 0 else {
            throw failure("disable", service: service, result: disabled)
        }

        let unloaded = try run(["bootout", service])
        // ESRCH and launchd's service-not-found are normal on fresh installations
        // and repeated launches. Other failures must not start a competing engine.
        guard [0, ESRCH, 113].contains(unloaded.status) else {
            throw failure("bootout", service: service, result: unloaded)
        }
    }

    private static func failure(_ action: String, service: String, result: CommandResult) -> Error {
        let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSError(domain: "Mugshot.LegacyAgentMigration", code: Int(result.status), userInfo: [
            NSLocalizedDescriptionKey: "launchctl \(action) \(service) failed (\(result.status)): \(detail)"
        ])
    }

    static func launchctl(_ arguments: [String]) throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self))
    }
}
