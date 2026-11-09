import Foundation
import Darwin

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}

@main
struct LegacyAgentMigrationChecks {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        if CommandLine.arguments.contains("--integration") {
            try integration()
            return
        }

        let expected = "gui/\(getuid())/com.lorenzo.faceid"
        for absentStatus: Int32 in [0, 3, 113] {
            var commands: [[String]] = []
            try LegacyAgentMigration.retire { arguments in
                commands.append(arguments)
                return .init(status: arguments.first == "disable" ? 0 : absentStatus, output: "")
            }
            try check(commands == [["disable", expected], ["bootout", expected]],
                      "The legacy job must be disabled persistently before it is unloaded")
        }

        var commands: [[String]] = []
        do {
            try LegacyAgentMigration.retire { arguments in
                commands.append(arguments)
                return .init(status: 1, output: "Operation not permitted")
            }
            throw CheckFailure(description: "A failed disable was reported as successful")
        } catch let failure as CheckFailure {
            throw failure
        } catch {
            try check(commands == [["disable", expected]],
                      "Do not unload a job that can still respawn after disable failed")
            try check(error.localizedDescription.contains("Operation not permitted"),
                      "Preserve the launchctl error for diagnostics")
        }

        do {
            try LegacyAgentMigration.retire { arguments in
                .init(status: arguments.first == "disable" ? 0 : 1, output: "Cannot unload")
            }
            throw CheckFailure(description: "A failed unload was reported as successful")
        } catch let failure as CheckFailure {
            throw failure
        } catch {
            try check(error.localizedDescription.contains("Cannot unload"),
                      "An unload failure must stop migration so a second engine cannot start")
        }
        print("OK: persistent disable, absent jobs, disable/unload failures and exact legacy target")
    }

    /// A real launchd job, isolated from Mugshot, PAM, the camera and Keychain.
    private static func integration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mugshot-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let label = "com.lorenzo.Mugshot.migration-test.\(UUID().uuidString)"
        let domain = "gui/\(getuid())"
        let service = "\(domain)/\(label)"
        let plist = directory.appendingPathComponent("agent.plist")
        let contents = try PropertyListSerialization.data(fromPropertyList: [
            "Label": label,
            "ProgramArguments": ["/bin/sleep", "300"],
            "RunAtLoad": true,
            "KeepAlive": true,
        ], format: .xml, options: 0)
        try contents.write(to: plist)
        defer {
            _ = try? LegacyAgentMigration.launchctl(["bootout", service])
            _ = try? LegacyAgentMigration.launchctl(["enable", service])
            try? FileManager.default.removeItem(at: directory)
        }

        let loaded = try LegacyAgentMigration.launchctl(["bootstrap", domain, plist.path])
        try check(loaded.status == 0, "Cannot load the isolated launchd fixture: \(loaded.output)")
        let before = try LegacyAgentMigration.launchctl(["print", service])
        try check(before.status == 0, "The legacy job must exist before migration")

        try LegacyAgentMigration.retire(service: service)
        let after = try LegacyAgentMigration.launchctl(["print", service])
        try check(after.status != 0, "FAIL: the legacy KeepAlive job is still loaded after migration")
        let disabled = try LegacyAgentMigration.launchctl(["print-disabled", domain])
        try check(disabled.status == 0 && disabled.output.contains("\"\(label)\" => disabled"),
                  "The job is stopped but not disabled for the next login")
        try check(try Data(contentsOf: plist) == contents, "Keep the legacy configuration recoverable")
        try LegacyAgentMigration.retire(service: service)
        print("OK: real KeepAlive job unloaded, persistently disabled, configuration preserved; repeated migration succeeds")
    }
}
