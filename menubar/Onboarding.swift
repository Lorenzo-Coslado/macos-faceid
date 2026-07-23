// Onboarding.swift — parcours guidé d'enrôlement du visage (SwiftUI).
import SwiftUI
import AVFoundation

final class EnrollController: ObservableObject {
    enum Phase { case intro, scanning, done, failed }
    @Published var phase: Phase = .intro
    @Published var count = 0
    @Published var total = 12
    @Published var message = ""
    private var proc: Process?

    var progress: Double { total > 0 ? min(1, Double(count) / Double(total)) : 0 }

    func reset() { phase = .intro; count = 0; message = "" }

    func begin() {
        // Demande l'accès caméra (prompt attribué à FaceID.app), puis lance le scan.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startScan()
        case .denied, .restricted:
            message = L("onb.cam.denied.full")
            phase = .failed
        default:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.startScan() }
                    else { self.message = L("onb.cam.denied"); self.phase = .failed }
                }
            }
        }
    }

    private func startScan() {
        phase = .scanning; count = 0; message = ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.python)
        p.arguments = ["-m", "faceid.enroll", "--json"]
        p.currentDirectoryURL = URL(fileURLWithPath: Paths.root)
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            for line in s.split(separator: "\n") {
                guard let d = line.data(using: .utf8),
                      let ev = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                else { continue }
                DispatchQueue.main.async { self.handle(ev) }
            }
        }
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                if self.phase == .scanning {
                    self.message = L("onb.interrupted")
                    self.phase = .failed
                }
            }
        }
        proc = p
        do { try p.run() } catch { message = "\(error)"; phase = .failed }
    }

    private func handle(_ ev: [String: Any]) {
        switch ev["event"] as? String {
        case "start": total = ev["n"] as? Int ?? total
        case "progress": count = ev["i"] as? Int ?? count
        case "done": count = total; phase = .done
        case "error": message = (ev["msg"] as? String) ?? "erreur"; phase = .failed
        default: break
        }
    }

    func cancel() { proc?.terminate() }
}

struct OnboardingView: View {
    @ObservedObject var c: EnrollController
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
                .frame(width: 440, height: 500)
        }
        .background(VisualEffect().ignoresSafeArea())
    }

    @ViewBuilder private var content: some View {
        switch c.phase {
        case .intro:    intro
        case .scanning: scanning
        case .done:     done
        case .failed:   failed
        }
    }

    private var logo: some View {
        Group {
            if let img = Brand.logo() { Image(nsImage: img).resizable() }
        }
        .frame(width: 96, height: 96)
    }

    private var intro: some View {
        VStack(spacing: 18) {
            logo.padding(.top, 8)
            Text(L("onb.title")).font(.system(size: 24, weight: .bold))
            Text(L("onb.intro"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 12) {
                tip("camera", L("onb.tip.light"))
                tip("arrow.left.and.right", L("onb.tip.move"))
                tip("lock.shield", L("onb.tip.local"))
            }
            .padding(.vertical, 6)
            Spacer()
            Button(action: c.begin) {
                Text(L("onb.start")).frame(maxWidth: .infinity)
            }
            .controlSize(.large).buttonStyle(.borderedProminent).tint(Brand.green)
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Brand.green).frame(width: 22)
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var scanning: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                Circle().trim(from: 0, to: c.progress)
                    .stroke(Brand.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: c.progress)
                logo.frame(width: 74, height: 74)
            }
            .frame(width: 150, height: 150)
            Text(L("onb.scanning")).font(.system(size: 17, weight: .semibold))
            Text(String(format: L("onb.captures"), c.count, c.total))
                .foregroundStyle(.secondary)
                .font(.system(size: 13).monospacedDigit())
            Text(L("onb.look"))
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 84)).foregroundStyle(Brand.green)
            Text(L("onb.done.title")).font(.system(size: 22, weight: .bold))
            Text(L("onb.done.body"))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .font(.system(size: 13))
            Spacer()
            Button(action: onFinish) { Text(L("onb.done.btn")).frame(maxWidth: .infinity) }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(Brand.green)
        }
    }

    private var failed: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 72)).foregroundStyle(.orange)
            Text(L("onb.fail.title")).font(.system(size: 20, weight: .bold))
            Text(c.message).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).font(.system(size: 12.5))
            Spacer()
            HStack {
                Button(L("onb.close"), action: onFinish).controlSize(.large)
                Button(L("onb.retry")) { c.reset() }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(Brand.green)
            }
        }
    }
}

/// Fond « verre » réutilisable.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
