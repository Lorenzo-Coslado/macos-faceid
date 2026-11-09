// Guided enrollment lives in an expansion of the camera notch.
import SwiftUI
import AVFoundation

final class EnrollController: ObservableObject {
    enum Phase { case intro, scanning, betweenPasses, done, failed }
    @Published var phase: Phase = .intro
    @Published var count = 0
    @Published var total = 18
    @Published var message = ""
    @Published var appending = false
    @Published var preview: NSImage?
    @Published var coverage = Array(repeating: 0.0, count: 8)
    @Published var passIndex = 1
    @Published var hint = "no-face"
    @Published var sector: Int?
    private var proc: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var session = UUID()
    private let streamQueue = DispatchQueue(label: "com.lorenzo.Mugshot.enrollment-stream")

    var progress: Double { total > 0 ? min(1, Double(count) / Double(total)) : 0 }

    func reset(appending: Bool? = nil) {
        cancel()
        phase = .intro; count = 0; message = ""; passIndex = 1
        coverage = Array(repeating: 0, count: 8)
        hint = "no-face"; sector = nil
        if let appending { self.appending = appending }
    }

    func begin() {
        guard phase == .intro else { return }
        let request = session
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startScan()
        case .denied, .restricted:
            message = L("onb.cam.denied.full"); phase = .failed
        default:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.session == request else { return }
                    if granted { self.startScan() }
                    else { self.message = L("onb.cam.denied"); self.phase = .failed }
                }
            }
        }
    }

    func continueScan() {
        guard phase == .betweenPasses, let input else { return }
        do {
            try input.fileHandleForWriting.write(contentsOf: Data("CONTINUE\n".utf8))
            phase = .scanning
            passIndex = 2; hint = "look-straight"
            coverage = Array(repeating: 0, count: 8)
        } catch {
            message = L("err.interrupted"); phase = .failed
            cancel()
        }
    }

    private func startScan() {
        guard proc == nil else { return }
        phase = .scanning; count = 0; message = ""
        let request = session
        let (exe, args) = Run.faceidCmd(["enroll", "--json", "--guided"] + (appending ? ["--append"] : []))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if !Paths.bundled { p.currentDirectoryURL = URL(fileURLWithPath: Paths.root) }
        var env = ProcessInfo.processInfo.environment
        env.merge(Paths.childEnv) { _, n in n }
        env.merge(Settings.shared.env) { _, n in n }
        p.environment = env
        let pipe = Pipe(), commands = Pipe(), stream = EnrollmentStream()
        input = commands; output = pipe
        p.standardOutput = pipe; p.standardInput = commands
        p.standardError = FileHandle.nullDevice
        let queue = streamQueue
        proc = p
        do { try p.run() }
        catch { message = "\(error)"; phase = .failed; cancel(); return }
        // One blocking reader owns the pipe. EOF follows all final JSON events,
        // so process exit can never overtake the done event.
        queue.async { [weak self] in
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                let events = stream.consume(data)
                DispatchQueue.main.async {
                    guard let self, self.session == request else { return }
                    for event in events { self.handle(event) }
                }
            }
            DispatchQueue.main.async {
                guard let self, self.session == request else { return }
                self.proc = nil; self.input = nil; self.output = nil
                if self.phase == .scanning || self.phase == .betweenPasses {
                    self.message = L("err.interrupted"); self.phase = .failed
                }
                self.preview = nil
            }
        }
    }

    private func handle(_ event: [String: Any]) {
        switch event["event"] as? String {
        case "start": total = event["n"] as? Int ?? total
        case "frame":
            if let jpeg = event["jpeg"] as? String, let data = Data(base64Encoded: jpeg) {
                preview = NSImage(data: data)
            }
            if event["passIndex"] as? Int == passIndex {
                hint = event["hint"] as? String ?? hint
                sector = event["sector"] as? Int
                if let values = event["coverage"] as? [Double], values.count == 8 { coverage = values }
            }
        case "progress":
            count = event["i"] as? Int ?? count
            if let values = event["coverage"] as? [Double], values.count == 8 { coverage = values }
        case "pass-complete": phase = .betweenPasses
        case "pass-start": passIndex = event["passIndex"] as? Int ?? 2
        case "done": count = total; phase = .done; preview = nil
        case "error": message = Self.describe(event["msg"] as? String); phase = .failed; preview = nil
        default: break
        }
    }

    static func describe(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return L("onb.fail.title") }
        let translated = L("err.\(code)")
        return translated == "err.\(code)" ? code : translated
    }

    func cancel() {
        session = UUID()
        try? input?.fileHandleForWriting.close()
        if let p = proc, p.isRunning { p.terminate() }
        proc = nil; input = nil; output = nil; preview = nil
    }
}

final class EnrollmentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }
}

struct EnrollmentIslandGeometry {
    let screen: NSScreen
    var attachment: CGFloat { screen.safeAreaInsets.top }
    var width: CGFloat { 390 }
    var height: CGFloat { 552 + attachment }
    var frame: NSRect {
        let left = screen.auxiliaryTopLeftArea, right = screen.auxiliaryTopRightArea
        let center = attachment > 0 && left != nil && right != nil
            ? (left!.maxX + right!.minX) / 2 : screen.visibleFrame.midX
        let top = attachment > 0 ? screen.frame.maxY : screen.visibleFrame.maxY - 8
        return NSRect(x: center - width / 2, y: top - height, width: width, height: height)
    }
}

private struct EnrollmentIslandShape: Shape {
    var attached: Bool
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 32
        var path = Path()
        if !attached { return Path(roundedRect: rect, cornerRadius: radius) }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct FaceScanRing: View {
    var coverage: [Double]
    var sector: Int?
    var complete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<72, id: \.self) { tick in
                let bucket = ((tick + 4) / 9) % 8
                let filled = complete || coverage[bucket] >= 1
                Capsule()
                    .fill(filled ? Brand.green : Color.white.opacity(sector == bucket ? 0.65 : 0.22))
                    .frame(width: 2.8, height: filled ? 17 : 8)
                    .offset(y: -116)
                    .rotationEffect(.degrees(Double(tick) * 5))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(Double(tick % 9) * 0.012), value: filled)
            }
        }
        .frame(width: 252, height: 252)
        .accessibilityHidden(true)
    }
}

struct OnboardingView: View {
    @ObservedObject var c: EnrollController
    var attachment: CGFloat = 0
    var onCancel: () -> Void
    var onFinish: () -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var complete: Bool { c.phase == .betweenPasses || c.phase == .done }
    private var capturing: Bool { c.phase == .scanning || c.phase == .betweenPasses }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Face ID").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel(L("onb.close"))
            }
            scanner
            VStack(spacing: 8) {
                Text(title).font(.system(size: 21, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(detail).font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 36, alignment: .top)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 24)
        .frame(width: 390, height: 552)
        .padding(.top, attachment)
        .foregroundStyle(.white)
        .background(.black)
        .clipShape(EnrollmentIslandShape(attached: attachment > 0))
        .scaleEffect(x: expanded ? 1 : 0.48, y: expanded ? 1 : 0.025, anchor: .top)
        .opacity(expanded ? 1 : 0)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.84)) { expanded = true }
        }
        .onExitCommand(perform: onCancel)
    }

    private var scanner: some View {
        ZStack {
            if capturing, let frame = c.preview {
                Image(nsImage: frame).resizable().scaledToFill()
                    .frame(width: 198, height: 198).clipShape(Circle())
                    .accessibilityLabel(L("onb.preview"))
            } else if c.phase == .scanning {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: c.phase == .done ? "checkmark" : c.phase == .failed ? "exclamationmark" : "faceid")
                    .font(.system(size: c.phase == .done ? 65 : 72, weight: .light))
                    .foregroundStyle(c.phase == .failed ? Color.orange : Brand.green)
            }
            Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .frame(width: 202, height: 202)
            FaceScanRing(coverage: c.coverage, sector: capturing ? c.sector : nil, complete: complete)
        }
        .frame(width: 252, height: 252)
    }

    private var title: String {
        switch c.phase {
        case .intro: return L(c.appending ? "onb.title.append" : "onb.title")
        case .scanning: return L(c.hint == "move" ? "onb.scan.move" : "onb.scan.position")
        case .betweenPasses: return L("onb.scan.first.done")
        case .done: return L("onb.done.title")
        case .failed: return L("onb.fail.title")
        }
    }

    private var detail: String {
        switch c.phase {
        case .intro: return L("onb.scan.intro")
        case .scanning: return L("onb.scan.hint.\(c.hint)")
        case .betweenPasses: return L("onb.scan.again")
        case .done: return L("onb.done.body")
        case .failed: return c.message
        }
    }

    @ViewBuilder private var footer: some View {
        switch c.phase {
        case .intro:
            action(L("onb.start"), c.begin)
            privacy
        case .scanning:
            HStack(spacing: 8) {
                ForEach(1...2, id: \.self) { pass in
                    Image(systemName: pass < c.passIndex ? "checkmark.circle.fill" : "circle.fill")
                        .font(.system(size: pass < c.passIndex ? 12 : 7))
                        .foregroundStyle(pass <= c.passIndex ? Brand.green : .white.opacity(0.2))
                }
                Text(String(format: L("onb.scan.pass"), c.passIndex))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            .frame(height: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: L("onb.scan.pass"), c.passIndex))
            .accessibilityValue(Text(c.progress, format: .percent.precision(.fractionLength(0))))
            Button(L("onb.scan.cancel"), action: onCancel).buttonStyle(.plain)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        case .betweenPasses:
            action(L("onb.scan.continue"), c.continueScan)
            privacy
        case .done:
            action(L("onb.done.btn"), onFinish)
            privacy
        case .failed:
            action(L("onb.retry")) { c.reset(); c.begin() }
            Button(L("onb.close"), action: onCancel).buttonStyle(.plain)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var privacy: some View {
        Label(L("onb.scan.local"), systemImage: "lock.fill")
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
    }

    private func action(_ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 42)
                .background(Brand.green, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain).keyboardShortcut(.defaultAction)
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
