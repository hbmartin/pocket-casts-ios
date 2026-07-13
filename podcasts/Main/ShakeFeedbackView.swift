import Capture
import PocketCastsServer
import PocketCastsUtils
import SwiftUI
import UIKit

/// Assembles the shake-to-report payload: the typed message plus the
/// diagnostics the sheet promises to attach (Deferred Item 67). Pure except for
/// the injected providers, so the report shape is unit-testable.
struct ShakeFeedbackReportBuilder {
    var logProvider: () async -> String = { await FileLog.shared.tailOfLogFile() }
    var sessionIDProvider: () -> String? = { Capture.Logger.sessionID }

    func report(message: String) async -> FeedbackReport {
        let device = UIDevice.current
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        return FeedbackReport(
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: "Shake report",
            logs: await logProvider(),
            bitdriftSessionID: sessionIDProvider() ?? "",
            deviceInfo: "\(device.model) \(device.systemName) \(device.systemVersion)",
            appVersion: "\(version) (\(build))"
        )
    }
}

/// Drives the shake-to-report sheet: message entry → send → sent/failed.
class ShakeFeedbackViewModel: ObservableObject {
    enum Phase: Equatable {
        case composing
        case sending
        case sent
        case failed
    }

    @Published var message = ""
    @Published private(set) var phase: Phase = .composing

    private let builder: ShakeFeedbackReportBuilder
    private let send: (FeedbackReport) async -> Bool

    init(builder: ShakeFeedbackReportBuilder = ShakeFeedbackReportBuilder(),
         send: @escaping (FeedbackReport) async -> Bool = { await ApiServerHandler.shared.sendFeedback(report: $0) }) {
        self.builder = builder
        self.send = send
    }

    var canSend: Bool {
        phase == .composing && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func sendTapped() {
        guard canSend else { return }
        phase = .sending
        Analytics.track(.shakeFeedbackSent)
        let message = message
        Task { [weak self] in
            guard let self else { return }
            let report = await self.builder.report(message: message)
            let success = await self.send(report)
            self.phase = success ? .sent : .failed
        }
    }

    /// A failed send returns to composing so the message isn't lost.
    func retryTapped() {
        phase = .composing
    }
}

/// The shake-to-report sheet shown in debug/TestFlight builds: a message field
/// with a note about the attached diagnostics.
struct ShakeFeedbackView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject var model: ShakeFeedbackViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var messageFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.shakeFeedbackTitle)
                .font(style: .title3, weight: .bold)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))

            switch model.phase {
            case .composing, .sending:
                composer
            case .sent:
                Label(L10n.shakeFeedbackSent, systemImage: "checkmark.circle.fill")
                    .font(style: .body, weight: .medium)
                    .foregroundColor(AppTheme.color(for: .support02, theme: theme))
                Button(L10n.done) { dismiss() }
                    .buttonStyle(.borderedProminent)
            case .failed:
                Text(L10n.shakeFeedbackFailed)
                    .font(style: .body, weight: .regular)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                Button(L10n.tryAgain) { model.retryTapped() }
                    .buttonStyle(.borderedProminent)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        .onAppear { messageFocused = true }
    }

    @ViewBuilder private var composer: some View {
        TextEditor(text: $model.message)
            .focused($messageFocused)
            .frame(minHeight: 120, maxHeight: 200)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.color(for: .primaryUi05, theme: theme)))
            .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            .disabled(model.phase == .sending)

        Text(L10n.shakeFeedbackDiagnosticsNote)
            .font(style: .caption, weight: .regular)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))

        Button {
            model.sendTapped()
        } label: {
            if model.phase == .sending {
                ProgressView()
            } else {
                Text(L10n.shakeFeedbackSend)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canSend)
    }
}
