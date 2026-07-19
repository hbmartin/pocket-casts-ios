import Contacts
import CryptoKit
import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// Find people (Slice 9, docs/Social.md): debounced prefix search over
/// discoverable profiles, friends-of-followed suggestions explained only as a
/// mutual-connection count, transient contacts matching (salted hashes of
/// every email and phone number per contact; emails match today, phone hashes
/// are wire-ready), and an invite row sharing the owner's Profile Link.
struct FindPeopleView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: FindPeopleViewModel
    @State private var showingContactsConsent = false

    var body: some View {
        List {
            Section {
                TextField(L10n.socialFindPeoplePlaceholder, text: $viewModel.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if !viewModel.results.isEmpty {
                Section(header: Text(L10n.socialFindResultsHeader)) {
                    ForEach(viewModel.results) { person in
                        personRow(person)
                    }
                }
            } else if viewModel.searchedWithNoResults {
                Section {
                    Text(L10n.socialSendRecipientNotFound)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            }

            if !viewModel.contactMatches.isEmpty {
                Section(header: Text(L10n.socialFindContactsHeader)) {
                    ForEach(viewModel.contactMatches) { person in
                        personRow(person)
                    }
                }
            }

            if !viewModel.suggestions.isEmpty {
                Section(header: Text(L10n.socialFindSuggestedHeader)) {
                    ForEach(viewModel.suggestions) { person in
                        personRow(person)
                    }
                }
            }

            Section {
                Button {
                    showingContactsConsent = true
                } label: {
                    Label(viewModel.isMatchingContacts ? L10n.socialFindContactsMatching : L10n.socialFindFromContacts,
                          systemImage: "person.crop.circle.badge.questionmark")
                }
                .disabled(viewModel.isMatchingContacts)
                Button {
                    viewModel.inviteFriend()
                } label: {
                    Label(L10n.socialFindInvite, systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(L10n.socialFindPeople)
        .navigationBarTitleDisplayMode(.inline)
        .alert(L10n.socialFindFromContacts, isPresented: $showingContactsConsent) {
            Button(L10n.socialFindContactsConsentCta) {
                Task { await viewModel.matchContacts() }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.socialFindContactsConsentBody)
        }
        .task { await viewModel.loadSuggestions() }
        .onChange(of: viewModel.query) { _, _ in viewModel.scheduleSearch() }
    }

    private func personRow(_ person: SocialProfileSummary) -> some View {
        Button {
            SocialCoordinator.openPublicProfile(handle: person.handle)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName.isEmpty ? "@" + person.handle : person.displayName)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    HStack(spacing: 4) {
                        Text("@" + person.handle)
                        if person.mutualCount > 0 {
                            Text("·")
                            Text(person.mutualCount == 1 ? L10n.socialFindMutualCountSingular : L10n.socialFindMutualCount(person.mutualCount))
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                Spacer()
                if person.yourFollowState == .active {
                    Text(L10n.socialFollowing)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                } else if person.yourFollowState == .pending {
                    Text(L10n.socialFollowRequested)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class FindPeopleViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [SocialProfileSummary] = []
    @Published private(set) var suggestions: [SocialProfileSummary] = []
    @Published private(set) var contactMatches: [SocialProfileSummary] = []
    @Published private(set) var searchedWithNoResults = false
    @Published private(set) var isMatchingContacts = false

    private var searchTask: Task<Void, Never>?
    private var fixtureLoaded = false

    init() {}

    /// Fixture initializer for snapshots/previews; loads then no-op.
    init(fixtureResults: [SocialProfileSummary] = [], suggestions: [SocialProfileSummary] = [],
         contactMatches: [SocialProfileSummary] = []) {
        results = fixtureResults
        self.suggestions = suggestions
        self.contactMatches = contactMatches
        fixtureLoaded = true
    }

    func loadSuggestions() async {
        guard !fixtureLoaded, SocialIdentityStore.isJoined else { return }
        Analytics.track(.socialPeopleShown)
        suggestions = await ApiServerHandler.shared.fetchPeopleSuggestions() ?? []
    }

    /// Debounce: a new keystroke supersedes the in-flight search.
    func scheduleSearch() {
        guard !fixtureLoaded else { return }
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            searchedWithNoResults = false
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            Analytics.track(.socialPeopleSearched)
            let found = await ApiServerHandler.shared.searchPeople(query: trimmed) ?? []
            guard !Task.isCancelled else { return }
            self.results = found
            self.searchedWithNoResults = found.isEmpty
        }
    }

    /// Contacts flow: permission → hash every email + phone per contact with
    /// the server salt → transient match. Nothing leaves the device but
    /// hashes; nothing is stored server-side.
    func matchContacts() async {
        guard !fixtureLoaded else { return }
        isMatchingContacts = true
        defer { isMatchingContacts = false }

        let store = CNContactStore()
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        guard granted, let salt = await ApiServerHandler.shared.fetchContactsSalt() else { return }

        let hashes = await Task.detached(priority: .userInitiated) { () -> [SocialContactHash] in
            var collected: [SocialContactHash] = []
            let keys = [CNContactEmailAddressesKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: request) { contact, _ in
                for email in contact.emailAddresses {
                    let normalized = (email.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                    guard !normalized.isEmpty else { continue }
                    collected.append(SocialContactHash(kind: 1, hash: Self.saltedHash(salt: salt, value: normalized)))
                }
                for phone in contact.phoneNumbers {
                    let digits = phone.value.stringValue.filter { $0.isNumber || $0 == "+" }
                    guard digits.count >= 7 else { continue }
                    collected.append(SocialContactHash(kind: 2, hash: Self.saltedHash(salt: salt, value: digits)))
                }
            }
            return Array(collected.prefix(2000))
        }.value

        guard !hashes.isEmpty else { return }
        let matches = await ApiServerHandler.shared.matchContacts(hashes: hashes) ?? []
        Analytics.track(.socialContactsMatched)
        contactMatches = matches
    }

    func inviteFriend() {
        guard let profile = SocialIdentityStore.cachedProfile,
              let url = URL(string: "\(ServerConstants.Urls.api())u/\(profile.handle)") else { return }
        guard var presenter = SceneHelper.rootViewController() else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activity, animated: true)
    }

    nonisolated static func saltedHash(salt: String, value: String) -> String {
        let digest = SHA256.hash(data: Data((salt + value).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
