import SwiftUI

/// The Explore tab: Apple top charts with a genre picker, plus directory
/// search. Everything on this screen works signed out and with zero
/// Pocket Casts servers.
struct ExploreView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = ExploreViewModel()

    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 16
        static let itemSpacing: CGFloat = 8
        static let coverCornerRadius: CGFloat = 8
        static let titleHeight: CGFloat = 32
    }

    private let columns = [
        GridItem(.flexible(), spacing: Layout.itemSpacing),
        GridItem(.flexible(), spacing: Layout.itemSpacing),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $model.searchTerm, placeholder: L10n.searchPodcasts)
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.vertical, 8)

            ScrollView {
                if model.isSearching {
                    searchResults
                } else {
                    chartContent
                }
            }
        }
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        .task {
            model.loadChartsIfNeeded()
        }
        .sheet(item: $model.previewedPodcast) { podcast in
            ExplorePodcastPreviewView(podcast: podcast, model: model)
                .environmentObject(theme)
        }
    }

    // MARK: - Charts

    private var chartContent: some View {
        LazyVStack(alignment: .leading, spacing: Layout.gridSpacing) {
            genrePicker

            switch model.chartState {
            case .idle, .loading:
                loadingView
            case .failed:
                failedView
            case .loaded(let podcasts):
                LazyVGrid(columns: columns, spacing: Layout.gridSpacing) {
                    ForEach(podcasts) { podcast in
                        chartGridItem(podcast)
                    }
                }
                .padding(.horizontal, Layout.horizontalPadding)
            }
        }
        .padding(.vertical, 12)
    }

    private var genrePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.itemSpacing) {
                genreChip(title: L10n.exploreAllCategories, isSelected: model.selectedGenre == nil) {
                    model.selectedGenre = nil
                }

                ForEach(ExploreGenre.allCases) { genre in
                    genreChip(title: genre.localizedName, isSelected: model.selectedGenre == genre) {
                        model.selectedGenre = genre
                    }
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
        }
    }

    private func genreChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(AppTheme.color(for: isSelected ? .primaryInteractive02 : .primaryText01, theme: theme))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(AppTheme.color(for: isSelected ? .primaryInteractive01 : .primaryUi05, theme: theme))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func chartGridItem(_ podcast: ExplorePodcast) -> some View {
        Button {
            model.previewedPodcast = podcast
        } label: {
            VStack(alignment: .leading, spacing: Layout.itemSpacing) {
                ExploreArtworkView(urlString: podcast.artworkURL)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.coverCornerRadius))

                Text(podcast.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // minHeight (not a fixed height) keeps single-line titles
                    // aligned while letting large Dynamic Type sizes grow past
                    // 32pt instead of clipping the second line.
                    .frame(minHeight: Layout.titleHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(podcast.title), \(podcast.author)"))
    }

    // MARK: - Search

    private var searchResults: some View {
        LazyVStack(spacing: 0) {
            switch model.searchState {
            case .idle, .loading:
                loadingView
            case .failed:
                failedView
            case .loaded(let podcasts):
                if podcasts.isEmpty {
                    emptyResultsView
                } else {
                    ForEach(podcasts) { podcast in
                        searchRow(podcast)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func searchRow(_ podcast: ExplorePodcast) -> some View {
        Button {
            model.previewedPodcast = podcast
        } label: {
            HStack(spacing: 12) {
                ExploreArtworkView(urlString: podcast.artworkURL)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(podcast.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                        .lineLimit(1)

                    Text(podcast.author)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - States

    private var loadingView: some View {
        ProgressView()
            .tint(AppTheme.color(for: .primaryIcon01, theme: theme))
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
    }

    private var failedView: some View {
        VStack(spacing: 12) {
            Text(L10n.exploreLoadFailed)
                .font(.subheadline)
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                .multilineTextAlignment(.center)

            Button(L10n.retry) {
                model.retry()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 80)
    }

    private var emptyResultsView: some View {
        Text(L10n.exploreNoResults)
            .font(.subheadline)
            .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
    }
}

/// Square artwork loaded through Kingfisher from Apple's artwork CDN, with a
/// themed placeholder while loading (or when the entry has no artwork).
struct ExploreArtworkView: View {
    @EnvironmentObject private var theme: Theme

    let urlString: String?

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImageView(url: url, cache: ImageManager.sharedManager.exploreImageCache)
                .background(AppTheme.color(for: .primaryUi05, theme: theme))
        } else {
            AppTheme.color(for: .primaryUi05, theme: theme)
        }
    }
}
