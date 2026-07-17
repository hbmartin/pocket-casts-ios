import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// The public review list for a podcast (Slice 3, docs/Social.md): attributed
/// text reviews with the author's stars, plus write/edit/delete for joined
/// accounts. Blocked authors are already filtered server-side; each row offers
/// content-level report and author block.
struct PodcastReviewsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: PodcastReviewsViewModel

    var body: some View {
        List {
            Section {
                Button {
                    viewModel.writeTapped()
                } label: {
                    Label(viewModel.yourReview == nil ? L10n.socialReviewWrite : L10n.socialReviewEdit,
                          systemImage: "square.and.pencil")
                }
            }

            if viewModel.reviews.isEmpty, !viewModel.isLoading {
                Section {
                    Text(L10n.socialReviewsEmpty)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            } else {
                Section(header: Text(L10n.socialReviewsCount(viewModel.total))) {
                    ForEach(viewModel.reviews) { review in
                        reviewRow(review)
                    }
                    if viewModel.canLoadMore {
                        Button(L10n.socialReviewsLoadMore) {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.socialReviewsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.showingEditor) {
            ReviewEditorView(viewModel: viewModel)
                .environmentObject(theme)
        }
        .confirmationDialog(L10n.socialReportTitle, isPresented: $viewModel.showingReportPicker, titleVisibility: .visible) {
            ForEach(PublicProfileViewModel.reportReasons, id: \.1) { label, reason in
                Button(label) { Task { await viewModel.reportSelected(reason: reason) } }
            }
            Button(L10n.cancel, role: .cancel) {}
        }
        .task { await viewModel.load() }
    }

    private func reviewRow(_ review: PodcastReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.displayName)
                        .font(.subheadline.bold())
                    Text("@" + review.handle)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                Spacer()
                if review.rating > 0 {
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { index in
                            Image(systemName: index < review.rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundColor(AppTheme.color(for: .filter03, theme: theme))
                        }
                    }
                }
                if review.userId != viewModel.ownUserId {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.reportTarget = review
                            viewModel.showingReportPicker = true
                        } label: {
                            Label(L10n.socialReport, systemImage: "flag")
                        }
                        Button(role: .destructive) {
                            Task { await viewModel.blockAuthor(review) }
                        } label: {
                            Label(L10n.socialBlock, systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(AppTheme.color(for: .primaryIcon02, theme: theme))
                    }
                }
            }
            Text(review.text)
                .font(.subheadline)
            if let createdAt = review.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Write/edit sheet: the text half of a review. Stars continue to ride the
/// existing rating sheet; this pairs with them rather than replacing them.
struct ReviewEditorView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject var viewModel: PodcastReviewsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text(L10n.socialReviewEditorNote).font(.footnote)) {
                    TextEditor(text: $viewModel.draftText)
                        .frame(minHeight: 140)
                }
                if let error = viewModel.editorError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                    }
                }
                if viewModel.yourReview != nil {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                if await viewModel.deleteReview() { dismiss() }
                            }
                        } label: {
                            Text(L10n.socialReviewDelete)
                        }
                    }
                }
            }
            .navigationTitle(L10n.socialReviewWrite)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Button(L10n.socialSave) {
                            Task {
                                if await viewModel.submitDraft() { dismiss() }
                            }
                        }
                        .disabled(viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

@MainActor
final class PodcastReviewsViewModel: ObservableObject {
    let podcastUuid: String
    let ownUserId: String?

    @Published private(set) var reviews: [PodcastReview] = []
    @Published private(set) var total = 0
    @Published private(set) var yourReview: PodcastReview?
    @Published private(set) var isLoading = true
    @Published private(set) var isSubmitting = false
    @Published var showingEditor = false
    @Published var showingReportPicker = false
    @Published var draftText = ""
    @Published private(set) var editorError: String?
    var reportTarget: PodcastReview?

    /// Fired when a not-joined user taps write — the host presents the Join flow.
    var onJoinRequired: (() -> Void)?

    private static let pageSize = 50

    init(podcastUuid: String, ownUserId: String? = ServerSettings.userId) {
        self.podcastUuid = podcastUuid
        self.ownUserId = ownUserId?.lowercased()
    }

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    convenience init(podcastUuid: String, fixture: PodcastReviewPage, ownUserId: String? = nil) {
        self.init(podcastUuid: podcastUuid, ownUserId: ownUserId)
        reviews = fixture.reviews
        total = fixture.total
        yourReview = fixture.yourReview
        isLoading = false
        fixtureLoaded = true
    }

    private var fixtureLoaded = false

    var canLoadMore: Bool { reviews.count < total }

    func load() async {
        guard !fixtureLoaded else { return }
        guard let page = await ApiServerHandler.shared.fetchReviews(podcastUuid: podcastUuid) else {
            isLoading = false
            return
        }
        reviews = page.reviews
        total = page.total
        yourReview = page.yourReview
        isLoading = false
    }

    func loadMore() async {
        guard let page = await ApiServerHandler.shared.fetchReviews(podcastUuid: podcastUuid,
                                                                    limit: Self.pageSize,
                                                                    offset: reviews.count) else { return }
        reviews.append(contentsOf: page.reviews)
        total = page.total
    }

    func writeTapped() {
        guard SocialIdentityStore.isJoined else {
            onJoinRequired?()
            return
        }
        draftText = yourReview?.text ?? ""
        editorError = nil
        showingEditor = true
    }

    func submitDraft() async -> Bool {
        isSubmitting = true
        editorError = nil
        let review = await ApiServerHandler.shared.submitReview(podcastUuid: podcastUuid,
                                                                text: draftText.trimmingCharacters(in: .whitespacesAndNewlines))
        isSubmitting = false
        guard review != nil else {
            // Rejection reasons: text filter, or the listen-gate.
            editorError = L10n.socialReviewRejected
            return false
        }
        Analytics.track(.socialReviewSubmitted)
        await load()
        return true
    }

    func deleteReview() async -> Bool {
        guard await ApiServerHandler.shared.deleteReview(podcastUuid: podcastUuid) else { return false }
        await load()
        return true
    }

    func reportSelected(reason: SocialReportReason) async {
        guard let target = reportTarget else { return }
        Analytics.track(.socialProfileReported)
        _ = await ApiServerHandler.shared.reportUser(targetUserId: target.userId,
                                                     reason: reason,
                                                     context: "review:\(podcastUuid)")
    }

    func blockAuthor(_ review: PodcastReview) async {
        DataManager.sharedManager.socialGraph.add(targetUserId: review.userId, handle: review.handle, type: .block)
        Analytics.track(.socialProfileBlocked)
        _ = await ApiServerHandler.shared.setBlocked(true, targetUserId: review.userId)
        await load()
    }
}
