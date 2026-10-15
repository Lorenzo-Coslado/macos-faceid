import SwiftUI
import AVFoundation

/// One resumable setup for the per-user permissions. The installer handles sudo;
/// camera and Accessibility consent must come from the logged-in user.
@MainActor
final class LockScreenSetupFlow: ObservableObject {
    enum Step: Equatable { case camera, accessibility, password, done }
    nonisolated static let pendingKey = "faceid.lockSetupPending"

    @Published private(set) var step: Step = .camera
    @Published private(set) var message = ""
    @Published private(set) var saving = false
    private var poll: Timer?
    private var running = false
    private var requestingCamera = false
    private var requestedAccessibility = false
    private var generation = 0

    struct Services {
        var cameraGranted: () -> Bool
        var requestCamera: (@escaping (Bool) -> Void) -> Void
        var canPostEvents: () -> Bool
        var requestEvents: () -> Void
        var passwordConfigured: () -> Bool
        var savePassword: (String) throws -> Void
        var enable: () -> Void
        var setPending: (Bool) -> Void

        static var live: Services {
            Services(
                cameraGranted: { AVCaptureDevice.authorizationStatus(for: .video) == .authorized },
                requestCamera: { completion in
                    if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .video) { granted in completion(granted) }
                    } else {
                        completion(AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
                    }
                },
                canPostEvents: { LockScreenAccessibility.isTrusted },
                requestEvents: { _ = LockScreenAccessibility.request(); LockScreenAccessibility.openSettings() },
                passwordConfigured: { LoginPasswordStore.isConfigured },
                savePassword: { try LoginPasswordStore.verifyAndSave($0) },
                enable: { Settings.shared.screenUnlockEnabled = true },
                setPending: { UserDefaults.standard.set($0, forKey: pendingKey) }
            )
        }
    }
    private let services: Services
    private let automaticallyPoll: Bool

    init(services: Services = .live, automaticallyPoll: Bool = true) {
        self.services = services
        self.automaticallyPoll = automaticallyPoll
    }

    func start() {
        guard !running else { return }
        running = true
        requestedAccessibility = false
        services.setPending(true)
        refresh()
        guard automaticallyPoll, running else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        running = false
        generation += 1
        requestingCamera = false
        poll?.invalidate()
        poll = nil
    }

    func cancel() {
        stop()
        services.setPending(false)
    }

    func refresh() {
        guard running else { return }
        if !services.cameraGranted() {
            step = .camera
            guard !requestingCamera else { return }
            requestingCamera = true
            let expected = generation
            services.requestCamera { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.running, self.generation == expected else { return }
                    if granted { self.requestingCamera = false; self.refresh() }
                    else { self.message = L("onb.cam.denied.full") }
                }
            }
            return
        }
        if !services.canPostEvents() {
            step = .accessibility
            message = ""
            if !requestedAccessibility {
                requestedAccessibility = true
                services.requestEvents()
            }
            return
        }
        if services.passwordConfigured() {
            complete()
        } else {
            if step != .password { message = "" }
            step = .password
        }
    }

    func save(_ password: String) {
        guard running, step == .password, !saving else { return }
        // Consent may have been revoked while the password form was open.
        guard services.cameraGranted(), services.canPostEvents() else { refresh(); return }
        saving = true
        message = ""
        let expected = generation
        let savePassword = services.savePassword
        // OpenDirectory password verification can block; keep the window responsive.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { try savePassword(password) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.saving = false
                guard self.running, self.generation == expected else { return }
                switch result {
                case .success: self.refresh()
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }

    private func complete() {
        services.enable()
        services.setPending(false)
        step = .done
        stop()
    }
}

struct LockScreenSetupSheet: View {
    @ObservedObject var flow: LockScreenSetupFlow
    var onClose: () -> Void
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("lock.setup.title")).font(.system(size: 20, weight: .bold))
            Text(L("lock.setup.intro")).font(.system(size: 12)).foregroundStyle(.secondary)
            row(L("lock.setup.camera"), done: flow.step != .camera)
            row(L("set.lockscreen.accessibility.short"), done: flow.step == .password || flow.step == .done)
            row(L("set.lockscreen.password.placeholder"), done: flow.step == .done)
            Divider()
            content
            if !flow.message.isEmpty {
                Text(flow.message).font(.system(size: 12)).foregroundStyle(.orange)
            }
            HStack {
                if flow.step != .done {
                    Button(L("lock.setup.later")) { flow.cancel(); password = ""; onClose() }
                        .disabled(flow.saving)
                }
                Spacer()
                if flow.step == .done {
                    Button(L("onb.close"), action: onClose).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(26).frame(width: 430)
        .onAppear { flow.start() }
        .onDisappear { flow.stop(); password = "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            flow.refresh()
        }
    }

    private func row(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? Brand.green : Color.secondary)
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .camera:
            Button(L("set.behavior.camera.system")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .accessibility:
            Text(L("lock.setup.waiting")).font(.system(size: 12))
            Button(L("set.lockscreen.accessibility.short")) { LockScreenAccessibility.openSettings() }
            Text(L("lock.setup.repair")).font(.system(size: 11)).foregroundStyle(.secondary)
            Button(L("lock.setup.restart"), action: restart)
        case .password:
            Text(L("set.lockscreen.password.desc")).font(.system(size: 12)).foregroundStyle(.secondary)
            SecureField(L("set.lockscreen.password.placeholder"), text: $password)
                .onSubmit(save)
                .disabled(flow.saving)
            Button(L("set.lockscreen.enable"), action: save)
                .buttonStyle(.borderedProminent).disabled(password.isEmpty || flow.saving)
        case .done:
            Text(L("set.lockscreen.enabled")).foregroundStyle(Brand.green)
        }
    }

    private func save() {
        flow.save(password)
        password = ""
    }

    private func restart() {
        // Pending state survives the restart. Arguments are separate shell parameters,
        // so paths containing quotes or spaces cannot change the command.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$1\" --args --setup",
                             "mugshot-restart", Bundle.main.bundleURL.path]
        do {
            try process.run()
            flow.stop()
            AppController.suppressQuitWarning = true
            NSApp.terminate(nil)
        } catch { flow.refresh() }
    }
}

extension Notification.Name {
    static let mugshotContinueSetup = Notification.Name("MugshotContinueSetup")
}
