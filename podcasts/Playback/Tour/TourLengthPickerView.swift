import PocketCastsUtils
import SwiftUI

/// The Highlights Tour sheet (S9): pick a length to start, then a live HUD of
/// the running tour (current stop, n of m, exit). One sheet, two phases,
/// re-rendered from `HighlightsTourStateChanged`.
struct TourLengthPickerView: View {
    @EnvironmentObject var theme: Theme
    @StateObject private var model = TourViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tourShelfTitle)
                .font(style: .title3, weight: .bold)
                .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))

            switch model.phase {
            case .pick:
                pickerBody
            case .preparing:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(AppTheme.loadingActivityColor().color)
                    Text(L10n.tourPreparing)
                        .font(style: .body)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            case .touring:
                hudBody
            case .failed:
                Text(L10n.tourPreparationFailed)
                    .font(style: .body)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    .padding(.vertical, 16)
            case .finished:
                Text(L10n.tourFinished)
                    .font(style: .body)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    .padding(.vertical, 16)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
    }

    @ViewBuilder private var pickerBody: some View {
        Toggle(L10n.tourSpokenTransitionsToggle, isOn: $model.spokenTransitions)
            .font(style: .body)

        ForEach(TourLength.allCases, id: \.self) { length in
            Button {
                model.start(length)
            } label: {
                HStack {
                    Text(length.displayableTitle)
                        .font(style: .body, weight: .medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.color(for: .primaryUi02, theme: theme)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var hudBody: some View {
        if let stopTitle = model.currentStopTitle {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.progressLine)
                    .font(style: .footnote, weight: .semibold)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                Text(stopTitle)
                    .font(style: .body, weight: .medium)
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
            }
            .padding(.vertical, 8)
        }

        Button(L10n.tourExit, role: .destructive) {
            model.exitTour()
        }
        .font(style: .body)
    }
}

@MainActor
final class TourViewModel: ObservableObject {
    enum Phase { case pick, preparing, touring, failed, finished }

    @Published private(set) var phase: Phase
    @Published var spokenTransitions: Bool {
        didSet { Settings.tourSpokenTransitionsEnabled = spokenTransitions }
    }

    private var stateToken: NotificationCenter.ObservationToken?

    init() {
        spokenTransitions = Settings.tourSpokenTransitionsEnabled
        phase = PlaybackManager.shared.isTouring ? .touring : .pick
        stateToken = NotificationCenter.default.addObserver(for: HighlightsTourStateChanged.self) { [weak self] _ in
            self?.refresh()
        }
    }

    isolated deinit {
        if let stateToken {
            NotificationCenter.default.removeObserver(stateToken)
        }
    }

    var currentStopTitle: String? {
        guard let controller = PlaybackManager.shared.tourController,
              let index = controller.currentStopIndex else { return nil }
        return controller.plan?.stops[index].title
    }

    var progressLine: String {
        guard let controller = PlaybackManager.shared.tourController,
              let index = controller.currentStopIndex,
              let count = controller.plan?.stops.count else { return "" }
        return L10n.tourProgress(String(index + 1), String(count))
    }

    func start(_ length: TourLength) {
        phase = .preparing
        PlaybackManager.shared.startHighlightsTour(length: length)
    }

    func exitTour() {
        PlaybackManager.shared.cancelHighlightsTour()
        phase = .pick
    }

    private func refresh() {
        guard let controller = PlaybackManager.shared.tourController else {
            phase = .pick
            return
        }
        switch controller.state {
        case .preparing:
            phase = .preparing
        case .cancelled(reason: .preparationFailed):
            phase = .failed
        case .cancelled:
            phase = .pick
        case .finished:
            phase = .finished
        default:
            phase = .touring
        }
    }
}
