import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// The send-to-friend sheet (Slice 4, docs/Social.md): address a joined
/// @handle (validated live — unknown and blocked answer identically), add an
/// optional note, and send the episode with an optional listen-from
/// timestamp. Recent recipients are remembered locally.
struct SendToFriendView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SendToFriendViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(L10n.socialSendRecipientHeader)) {
                    HStack {
                        Text("@")
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        TextField(L10n.socialHandlePlaceholder, text: $viewModel.handleInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    recipientStatus
                    if !viewModel.recentRecipients.isEmpty {
                        ForEach(viewModel.recentRecipients, id: \.self) { handle in
                            Button("@" + handle) { viewModel.handleInput = handle }
                                .font(.footnote)
                        }
                    }
                }

                Section(header: Text(L10n.socialSendNoteHeader)) {
                    TextField(L10n.socialSendNotePlaceholder, text: $viewModel.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.episodeTitle)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if viewModel.timestampSeconds > 0 {
                            Text(L10n.socialSendFromTimestamp(TimeFormatter.shared.playTimeFormat(time: TimeInterval(viewModel.timestampSeconds))))
                                .font(.footnote)
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        }
                    }
                }

                if let error = viewModel.sendError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                    }
                }
            }
            .navigationTitle(L10n.socialSendTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSending {
                        ProgressView()
                    } else {
                        Button(L10n.socialSendCta) {
                            Task {
                                if await viewModel.send() { dismiss() }
                            }
                        }
                        .disabled(!viewModel.recipientValid)
                    }
                }
            }
        }
    }

    @ViewBuilder private var recipientStatus: some View {
        switch viewModel.recipientStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.socialHandleChecking)
            }
            .font(.footnote)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        case .found(let name):
            Label(name, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .support02, theme: theme))
        case .notFound:
            Label(L10n.socialSendRecipientNotFound, systemImage: "xmark.circle.fill")
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .support05, theme: theme))
        }
    }
}

@MainActor
final class SendToFriendViewModel: ObservableObject {
    enum RecipientStatus: Equatable { case idle, checking, found(name: String), notFound }

    static let recentRecipientsKey = "SocialRecentRecipients"

    let episodeUuid: String
    let podcastUuid: String
    let episodeTitle: String
    let podcastTitle: String
    let timestampSeconds: Int

    @Published var handleInput = "" { didSet { scheduleLookup() } }
    @Published var note = ""
    // Internal setter: snapshot tests stage specific states.
    @Published var recipientStatus: RecipientStatus = .idle
    @Published private(set) var isSending = false
    @Published private(set) var sendError: String?

    private var lookupTask: Task<Void, Never>?

    var recentRecipients: [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentRecipientsKey) ?? []
    }

    var recipientValid: Bool {
        if case .found = recipientStatus { return true }
        return false
    }

    init(episodeUuid: String, podcastUuid: String, episodeTitle: String, podcastTitle: String, timestampSeconds: Int) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.timestampSeconds = timestampSeconds
    }

    func send() async -> Bool {
        let handle = normalized(handleInput)
        isSending = true
        sendError = nil
        let sent = await ApiServerHandler.shared.sendSharedItem(recipientHandle: handle,
                                                                episodeUuid: episodeUuid,
                                                                podcastUuid: podcastUuid,
                                                                episodeTitle: episodeTitle,
                                                                podcastTitle: podcastTitle,
                                                                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                timestampSeconds: timestampSeconds)
        isSending = false
        guard sent else {
            sendError = L10n.socialSendFailed
            return false
        }
        rememberRecipient(handle)
        Analytics.track(.socialItemSent)
        Toast.show(L10n.socialSendSuccess("@" + handle))
        return true
    }

    private func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
    }

    private func scheduleLookup() {
        lookupTask?.cancel()
        let candidate = normalized(handleInput)
        guard !candidate.isEmpty else {
            recipientStatus = .idle
            return
        }
        recipientStatus = .checking
        lookupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            let profile = await ApiServerHandler.shared.fetchPublicProfile(handle: candidate)
            guard !Task.isCancelled, self.normalized(self.handleInput) == candidate else { return }
            if let profile {
                self.recipientStatus = .found(name: profile.displayName)
            } else {
                self.recipientStatus = .notFound
            }
        }
    }

    private func rememberRecipient(_ handle: String) {
        var recents = recentRecipients.filter { $0 != handle }
        recents.insert(handle, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(5)), forKey: Self.recentRecipientsKey)
    }
}
