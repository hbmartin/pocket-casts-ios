import PocketCastsUtils
import SwiftUI

/// Visual query editor: a recursive tree of All/Any groups over condition rows.
/// The engine caps (depth, children per group, total conditions) are enforced by
/// the view model; this view hides or disables the affordances at the limits.
struct CustomQueryBuilderView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var viewModel: CustomPlaylistEditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CustomQueryGroupView(viewModel: viewModel, group: viewModel.document, depth: 1, onDelete: nil)

                if viewModel.builderHasIncompleteConditions {
                    Text(L10n.playlistCustomBuilderIncompleteWarning)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.color(for: .support05, theme: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                previewSection
            }
            .padding(16)
        }
    }

    @ViewBuilder private var previewSection: some View {
        if let matchCount = viewModel.previewMatchCount {
            VStack(alignment: .leading, spacing: 8) {
                Text(matchCountText(matchCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))

                ForEach(viewModel.previewEpisodes.prefix(3), id: \.episode.uuid) { listEpisode in
                    Text(listEpisode.episode.title ?? "")
                        .font(.footnote)
                        .lineLimit(1)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                }
            }
        }
    }

    private func matchCountText(_ count: Int) -> String {
        count == 1
            ? L10n.playlistCustomMatchCountSingular(count.localized(.decimal))
            : L10n.playlistCustomMatchCountPlural(count.localized(.decimal))
    }
}

/// One group in the tree: an All/Any header, its child rows (conditions and
/// nested groups, rendered recursively), and the add buttons.
struct CustomQueryGroupView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var viewModel: CustomPlaylistEditorViewModel

    let group: CustomQueryDraftGroup
    let depth: Int
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ForEach(group.children) { child in
                switch child {
                case .condition(let condition):
                    CustomQueryConditionRow(viewModel: viewModel, condition: condition)
                case .group(let nestedGroup):
                    CustomQueryGroupView(
                        viewModel: viewModel,
                        group: nestedGroup,
                        depth: depth + 1,
                        onDelete: { viewModel.removeNode(id: nestedGroup.id) }
                    )
                }
            }

            if group.children.isEmpty {
                Text(L10n.playlistCustomBuilderEmptyDescription)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            addButtons
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.color(for: depth % 2 == 1 ? .primaryUi02 : .primaryUi01, theme: theme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.color(for: .primaryUi05, theme: theme), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker(L10n.playlistCustomConditionOperator, selection: matchBinding) {
                Text(L10n.playlistCustomGroupAll).tag(CustomQueryDraftGroup.Match.all)
                Text(L10n.playlistCustomGroupAny).tag(CustomQueryDraftGroup.Match.any)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Text(matchDescription)
                .font(.footnote)
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                .lineLimit(2)

            Spacer(minLength: 0)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.color(for: .primaryIcon03, theme: theme))
                }
                .accessibilityLabel(L10n.playlistCustomRemoveRule)
            }
        }
    }

    private var matchDescription: String {
        switch group.match {
        case .all: L10n.playlistCustomGroupMatchAllDescription
        case .any: L10n.playlistCustomGroupMatchAnyDescription
        }
    }

    private var matchBinding: Binding<CustomQueryDraftGroup.Match> {
        Binding(
            get: { group.match },
            set: { viewModel.setGroupMatch($0, groupID: group.id) }
        )
    }

    private var addButtons: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.addCondition(toGroupID: group.id)
            } label: {
                Label(L10n.playlistCustomAddCondition, systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(!viewModel.canAddCondition(to: group))

            // The depth cap hides "add group" entirely at the maximum depth.
            if depth < CustomQueryLimits.maxDepth {
                Button {
                    viewModel.addGroup(toGroupID: group.id)
                } label: {
                    Label(L10n.playlistCustomAddGroup, systemImage: "plus.rectangle.on.rectangle")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(!viewModel.canAddGroup(to: group))
            }
        }
        .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
    }
}
