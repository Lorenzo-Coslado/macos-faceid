// SetupSheet.swift — les trois autorisations macOS, montrées d'un seul tenant.
//
// macOS en exige trois pour brancher Face ID sur sudo, et aucune ne peut être supprimée
// depuis l'app : autoriser le daemon privilégié, lui donner l'Accès complet au disque,
// écrire la règle PAM. Ce qu'on peut supprimer, c'est l'impression d'échec entre les
// trois — l'utilisateur voit la liste entière dès le départ, chaque ligne se coche seule
// quand il revient des Réglages système, et il n'a jamais à relancer ce qu'il a déjà fait.
import SwiftUI

struct SetupSheet: View {
    @ObservedObject var flow: SetupFlow
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("setup.title")).font(.system(size: 17, weight: .bold))
                Text(L("setup.intro"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 18)

            VStack(spacing: 0) {
                ForEach(SetupFlow.Step.allCases) { step in
                    row(step)
                    if step != SetupFlow.Step.allCases.last { Divider().padding(.leading, 52) }
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 18)

            HStack {
                if case .failed = flow.state(.rule) {
                    Button(L("onb.retry")) { flow.reset(); flow.start() }
                        .tint(Brand.green)
                }
                Spacer()
                Button(flow.finished ? L("setup.done") : L("onb.close"), action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(flow.finished ? Brand.green : .gray)
            }
            .padding(.horizontal, 24).padding(.bottom, 22)
        }
        .frame(width: 460, height: 420)
        .background(VisualEffect().ignoresSafeArea())
        .onDisappear { flow.stop() }
    }

    @ViewBuilder private func row(_ step: SetupFlow.Step) -> some View {
        let state = flow.state(step)
        HStack(alignment: .top, spacing: 14) {
            marker(state)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(L(step.titleKey))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isDone(state) ? .secondary : .primary)
                Text(detail(step, state))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Le raccourci n'apparaît que sur l'étape en attente : proposer d'ouvrir
            // des Réglages qu'on n'a pas encore à toucher est un piège.
            if case .active = state, step != .rule {
                Button(L("setup.open")) { flow.openSystemSettings(for: step) }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder private func marker(_ state: SetupFlow.StepState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19)).foregroundStyle(Brand.green)
        case .active:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18)).foregroundStyle(.orange)
        case .pending:
            Image(systemName: "circle.dashed")
                .font(.system(size: 18)).foregroundStyle(.tertiary)
        }
    }

    private func isDone(_ s: SetupFlow.StepState) -> Bool {
        if case .done = s { return true }
        return false
    }

    private func detail(_ step: SetupFlow.Step, _ state: SetupFlow.StepState) -> String {
        switch state {
        case .failed(let msg): return msg
        case .active where step == .helper:   return L("setup.step.helper.waiting")
        case .active where step == .fullDisk: return L("setup.step.fda.waiting")
        default: return L(step.detailKey)
        }
    }
}
