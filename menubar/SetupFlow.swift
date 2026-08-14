// SetupFlow.swift — activation de Face ID pour sudo, présentée comme une suite
// d'étapes qui se valident seules.
//
// Avant, c'était un interrupteur : on le basculait, il échouait, il revenait à zéro, une
// ligne de texte gris expliquait quoi faire, et il fallait le rebasculer. Trois fois, car
// macOS exige deux autorisations distinctes. Rien ne disait où on en était.
//
// Ici les trois étapes sont visibles d'emblée, et l'app surveille l'état du système :
// quand l'utilisateur revient des Réglages, l'étape se coche et la suivante démarre. Il
// n'a jamais à recommencer une action déjà faite.
import SwiftUI
import ServiceManagement

@MainActor
final class SetupFlow: ObservableObject {

    enum StepState: Equatable {
        case pending      // pas encore atteinte
        case active       // en cours, on attend l'utilisateur ou le système
        case done
        case failed(String)
    }

    enum Step: Int, CaseIterable, Identifiable {
        case helper        // autoriser le daemon privilégié (Éléments d'ouverture)
        case fullDisk      // Accès complet au disque pour ce daemon
        case rule          // écriture de la règle PAM

        var id: Int { rawValue }

        var titleKey: String {
            switch self {
            case .helper:   return "setup.step.helper"
            case .fullDisk: return "setup.step.fda"
            case .rule:     return "setup.step.rule"
            }
        }
        var detailKey: String {
            switch self {
            case .helper:   return "setup.step.helper.detail"
            case .fullDisk: return "setup.step.fda.detail"
            case .rule:     return "setup.step.rule.detail"
            }
        }
    }

    @Published private(set) var states: [Step: StepState] = [:]
    @Published private(set) var running = false
    /// Vrai une fois la règle PAM en place — l'app peut refermer la fenêtre d'étapes.
    @Published private(set) var finished = false

    private var poll: Timer?

    init() { reset() }

    func reset() {
        states = [.helper: .pending, .fullDisk: .pending, .rule: .pending]
        finished = false
    }

    func state(_ s: Step) -> StepState { states[s] ?? .pending }

    /// L'étape sur laquelle l'utilisateur doit agir, s'il y en a une.
    var currentStep: Step? {
        Step.allCases.first { if case .done = state($0) { return false }; return true }
    }

    // MARK: déroulé

    /// Démarre (ou reprend) la séquence. Idempotent : appelable à chaque réouverture
    /// de la fenêtre sans refaire ce qui est déjà acquis.
    func start() {
        guard !running else { return }
        running = true
        advance()
    }

    func stop() {
        poll?.invalidate(); poll = nil
        running = false
    }

    private func advance() {
        guard running else { return }
        switch currentStep {
        case .none:
            finished = true
            stop()
        case .helper:
            registerHelper()
        case .fullDisk:
            checkFullDisk()
        case .rule:
            writeRule()
        }
    }

    // 1. Enregistrement du daemon privilégié.
    private func registerHelper() {
        states[.helper] = .active
        switch HelperManager.shared.ensureRegistered() {
        case .enabled:
            states[.helper] = .done
            advance()
        case .needsApproval:
            // macOS a ouvert les Éléments d'ouverture. On attend que l'utilisateur
            // bascule l'entrée, sans rien lui demander de plus.
            waitFor({ HelperManager.shared.isEnabled }) { [weak self] in
                self?.states[.helper] = .done
                self?.advance()
            }
        case .failed(let e):
            states[.helper] = .failed(e)
            running = false
        }
    }

    // 2. Accès complet au disque — demandé AVANT d'essayer d'écrire.
    private func checkFullDisk() {
        states[.fullDisk] = .active
        HelperManager.shared.checkAccess { [weak self] ok, _ in
            guard let self else { return }
            if ok {
                self.states[.fullDisk] = .done
                self.advance()
            } else {
                // Le volet se rouvre une seule fois ; ensuite on se contente d'attendre.
                HelperManager.shared.openFullDiskAccess()
                self.waitForAccess()
            }
        }
    }

    /// Sonde périodiquement le helper. Il s'arrête tout seul après 20 s d'inactivité,
    /// et c'est justement ce qui permet à une autorisation TCC fraîche d'être prise en
    /// compte : le processus suivant démarre avec le nouveau droit.
    private func waitForAccess() {
        var lastMessage = ""
        startPolling(every: 2.0, giveUpAfter: Self.waitBudget) { [weak self] finish in
            HelperManager.shared.checkAccess { ok, msg in
                lastMessage = msg
                if ok { finish() }
            }
            _ = self
        } onTimeout: { [weak self] in
            self?.states[.fullDisk] = .failed(lastMessage.isEmpty
                                              ? L("setup.step.fda.waiting") : lastMessage)
            self?.running = false
        } onSuccess: { [weak self] in
            self?.states[.fullDisk] = .done
            self?.advance()
        }
    }

    // 3. Écriture de la règle PAM.
    private func writeRule() {
        states[.rule] = .active
        HelperManager.shared.enableSudo { [weak self] ok, msg in
            guard let self else { return }
            self.states[.rule] = ok ? .done : .failed(msg)
            if ok { self.finished = true }
            self.running = false
            self.stop()
        }
    }

    /// Attend qu'une condition système devienne vraie, sans bloquer l'interface.
    private func waitFor(_ condition: @escaping () -> Bool,
                         then done: @escaping () -> Void) {
        startPolling(every: 1.0, giveUpAfter: Self.waitBudget) { finish in
            if condition() { finish() }
        } onTimeout: { [weak self] in
            self?.states[.helper] = .failed(L("setup.step.helper.waiting"))
            self?.running = false
        } onSuccess: { done() }
    }

    /// Combien de temps on attend une action dans les Réglages système avant de rendre
    /// la main. Sans borne, une étape qui ne viendra jamais tourne indéfiniment et la
    /// fenêtre reste bloquée sur un indicateur d'activité sans rien expliquer.
    private static let waitBudget: TimeInterval = 180

    /// Sondage périodique borné dans le temps. `probe` reçoit une closure à appeler
    /// quand la condition est remplie ; elle peut être invoquée de façon asynchrone.
    private func startPolling(every interval: TimeInterval,
                              giveUpAfter budget: TimeInterval,
                              probe: @escaping (@escaping () -> Void) -> Void,
                              onTimeout: @escaping () -> Void,
                              onSuccess: @escaping () -> Void) {
        poll?.invalidate()
        let deadline = Date().addingTimeInterval(budget)
        var settled = false
        poll = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.running, !settled else { return }
                if Date() >= deadline {
                    settled = true
                    self.poll?.invalidate(); self.poll = nil
                    onTimeout()
                    return
                }
                probe {
                    Task { @MainActor in
                        guard !settled else { return }
                        settled = true
                        self.poll?.invalidate(); self.poll = nil
                        onSuccess()
                    }
                }
            }
        }
    }

    /// Rouvre le volet des Réglages système correspondant à l'étape en cours.
    func openSystemSettings(for step: Step) {
        switch step {
        case .helper:   SMAppService.openSystemSettingsLoginItems()
        case .fullDisk: HelperManager.shared.openFullDiskAccess()
        case .rule:     break
        }
    }
}
