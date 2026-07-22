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
    @EnvironmentObject private var theme: Theme
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

            if !viewModel.curators.isEmpty {
                Section(header: Text(L10n.socialCuratorsHeader)) {
                    ForEach(viewModel.curators) { person in
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

            if let error = viewModel.loadError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .support05, theme: theme))
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
                    HStack(spacing: 4) {
                        Text(person.displayName.isEmpty ? "@" + person.handle : person.displayName)
                            .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                        if person.curator {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                                .accessibilityLabel(L10n.socialCuratorBadge)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("@" + person.handle)
                        if person.curator, person.followerCount > 0 {
                            Text("·")
                            Text(person.followerCount == 1 ? L10n.socialCuratorFollowersSingular : L10n.socialCuratorFollowers(person.followerCount))
                        }
                        if person.mutualCount > 0 {
                            Text("·")
                            Text(person.mutualCount == 1 ? L10n.socialFindMutualCountSingular : L10n.socialFindMutualCountPlural(person.mutualCount))
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
    typealias SearchPeople = (String) async -> Result<[SocialProfileSummary], SocialPeopleRequestError>
    typealias LoadPeople = () async -> Result<[SocialProfileSummary], SocialPeopleRequestError>
    typealias LoadContactsSalt = () async -> Result<String, SocialPeopleRequestError>
    typealias MatchContacts = ([SocialContactHash]) async -> Result<[SocialProfileSummary], SocialPeopleRequestError>

    @Published var query = ""
    @Published private(set) var results: [SocialProfileSummary] = []
    @Published private(set) var suggestions: [SocialProfileSummary] = []
    @Published private(set) var curators: [SocialProfileSummary] = []
    @Published private(set) var contactMatches: [SocialProfileSummary] = []
    @Published private(set) var searchedWithNoResults = false
    @Published private(set) var isMatchingContacts = false
    @Published private(set) var loadError: String?

    private var searchTask: Task<Void, Never>?
    private var fixtureLoaded = false
    private let isJoined: () -> Bool
    private let searchPeople: SearchPeople
    private let loadPeopleSuggestions: LoadPeople
    private let loadCurators: LoadPeople
    private let loadContactsSalt: LoadContactsSalt
    private let matchContactHashes: MatchContacts

    init(
        isJoined: @escaping () -> Bool = { SocialIdentityStore.isJoined },
        searchPeople: @escaping SearchPeople = { await ApiServerHandler.shared.searchPeople(query: $0) },
        loadPeopleSuggestions: @escaping LoadPeople = { await ApiServerHandler.shared.fetchPeopleSuggestions() },
        loadCurators: @escaping LoadPeople = { await ApiServerHandler.shared.fetchCurators() },
        loadContactsSalt: @escaping LoadContactsSalt = { await ApiServerHandler.shared.fetchContactsSalt() },
        matchContactHashes: @escaping MatchContacts = { await ApiServerHandler.shared.matchContacts(hashes: $0) }
    ) {
        self.isJoined = isJoined
        self.searchPeople = searchPeople
        self.loadPeopleSuggestions = loadPeopleSuggestions
        self.loadCurators = loadCurators
        self.loadContactsSalt = loadContactsSalt
        self.matchContactHashes = matchContactHashes
    }

    /// Fixture initializer for snapshots/previews; loads then no-op.
    init(fixtureResults: [SocialProfileSummary] = [], suggestions: [SocialProfileSummary] = [],
         contactMatches: [SocialProfileSummary] = [], curators: [SocialProfileSummary] = []) {
        results = fixtureResults
        self.suggestions = suggestions
        self.contactMatches = contactMatches
        self.curators = curators
        isJoined = { false }
        searchPeople = { _ in .success([]) }
        loadPeopleSuggestions = { .success([]) }
        loadCurators = { .success([]) }
        loadContactsSalt = { .success("") }
        matchContactHashes = { _ in .success([]) }
        fixtureLoaded = true
    }

    func loadSuggestions() async {
        guard !fixtureLoaded, isJoined() else { return }
        Analytics.track(.socialPeopleShown)
        loadError = nil
        switch await loadPeopleSuggestions() {
        case .success(let loaded):
            suggestions = loaded
        case .failure:
            loadError = L10n.socialFindLoadFailed
        }
        switch await loadCurators() {
        case .success(let loaded):
            curators = loaded
        case .failure:
            loadError = L10n.socialFindLoadFailed
        }
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
            await self.performSearch(query: trimmed)
        }
    }

    func performSearch(query: String) async {
        let result = await searchPeople(query)
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let found):
            loadError = nil
            results = found
            searchedWithNoResults = found.isEmpty
        case .failure:
            results = []
            searchedWithNoResults = false
            loadError = L10n.socialFindLoadFailed
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
        guard granted else { return }
        let salt: String
        switch await loadContactsSalt() {
        case .success(let loaded):
            salt = loaded
        case .failure:
            loadError = L10n.socialFindLoadFailed
            return
        }

        let hashes = await Task.detached(priority: .userInitiated) { () -> [SocialContactHash] in
            var collected: [SocialContactHash] = []
            let keys = [CNContactEmailAddressesKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: request) { contact, _ in
                for email in contact.emailAddresses {
                    let normalized = (email.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                    guard !normalized.isEmpty else { continue }
                    collected.append(SocialContactHash(kind: .email, hash: Self.saltedHash(salt: salt, value: normalized)))
                }
                for phone in contact.phoneNumbers {
                    let digits = phone.value.stringValue.filter { $0.isNumber || $0 == "+" }
                    guard digits.count >= 7 else { continue }
                    collected.append(SocialContactHash(kind: .phone, hash: Self.saltedHash(salt: salt, value: digits)))
                }
            }
            return Array(collected.prefix(2000))
        }.value

        guard !hashes.isEmpty else { return }
        await loadContactMatches(hashes)
    }

    func loadContactMatches(_ hashes: [SocialContactHash]) async {
        switch await matchContactHashes(hashes) {
        case .success(let matches):
            loadError = nil
            Analytics.track(.socialContactsMatched)
            contactMatches = matches
        case .failure:
            contactMatches = []
            loadError = L10n.socialFindLoadFailed
        }
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
