import PocketCastsDataModel
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshots for the custom playlist editor (plan section G): the
/// builder in its empty / nested / incomplete states and the SQL editor in its
/// valid / invalid states, each across all nine app themes.
@MainActor
final class CustomPlaylistSnapshotTests: XCTestCase {
    private func makeViewModel() -> CustomPlaylistEditorViewModel {
        var draft = EpisodeFilter()
        draft.uuid = "snapshot-custom-playlist"
        draft.playlistName = "Snapshot Playlist"
        return CustomPlaylistEditorViewModel(
            draft: draft,
            mode: .creation,
            validator: { _ in .failure(.empty) },
            smartRulesFragmentProvider: { _ in "" },
            livePreviewEnabled: false
        )
    }

    private func setValue(_ mutate: (inout CustomQueryDraftCondition) -> Void, onLastConditionIn groupID: UUID, of viewModel: CustomPlaylistEditorViewModel) {
        guard let group = viewModel.document.group(withID: groupID) else { XCTFail("missing group")
return }
        for child in group.children.reversed() {
            if case .condition(var condition) = child {
                mutate(&condition)
                viewModel.updateCondition(condition)
                return
            }
        }
        XCTFail("missing condition in group")
    }

    // MARK: - Builder

    func testBuilderEmpty() {
        assertAppThemedSnapshots(
            of: CustomQueryBuilderView(viewModel: makeViewModel()),
            layout: .fixed(width: 390, height: 360)
        )
    }

    func testBuilderNestedGroups() {
        let viewModel = makeViewModel()

        // Root: title contains "interview", plus an Any group with two number rules.
        viewModel.addCondition(toGroupID: viewModel.document.id)
        setValue({ $0.value.text = "interview" }, onLastConditionIn: viewModel.document.id, of: viewModel)

        viewModel.addGroup(toGroupID: viewModel.document.id)
        guard case .group(let nested)? = viewModel.document.children.last else { XCTFail("missing nested group")
return }

        viewModel.addCondition(toGroupID: nested.id)
        setValue({ condition in
            condition = condition.changingField(to: .duration)
                .changingOperator(to: .greaterThan)
            condition.value.numberText = "3600"
        }, onLastConditionIn: nested.id, of: viewModel)

        viewModel.addCondition(toGroupID: nested.id)
        setValue({ condition in
            condition = condition.changingField(to: .seasonNumber)
                .changingOperator(to: .between)
            condition.value.numberText = "1"
            condition.value.secondNumberText = "3"
        }, onLastConditionIn: nested.id, of: viewModel)

        assertAppThemedSnapshots(
            of: CustomQueryBuilderView(viewModel: viewModel),
            layout: .fixed(width: 390, height: 760)
        )
    }

    func testBuilderIncompleteConditionWarning() {
        let viewModel = makeViewModel()
        // A default condition with no value: red row border + inline warning.
        viewModel.addCondition(toGroupID: viewModel.document.id)

        assertAppThemedSnapshots(
            of: CustomQueryBuilderView(viewModel: viewModel),
            layout: .fixed(width: 390, height: 420)
        )
    }

    // MARK: - SQL

    func testSQLValidWithMatchCount() {
        let viewModel = makeViewModel()
        viewModel.editorMode = .sql
        viewModel.sqlText = "episode.duration > 1800 AND podcast.title LIKE '%history%'"
        viewModel.applyValidationResult(.success(42))

        assertAppThemedSnapshots(
            of: CustomQuerySQLView(viewModel: viewModel),
            layout: .fixed(width: 390, height: 560)
        )
    }

    func testSQLInvalidWithInlineError() {
        let viewModel = makeViewModel()
        viewModel.editorMode = .sql
        viewModel.sqlText = "episode.duration >"
        viewModel.applyValidationResult(.failure(.syntax(message: "incomplete input")))

        assertAppThemedSnapshots(
            of: CustomQuerySQLView(viewModel: viewModel),
            layout: .fixed(width: 390, height: 560)
        )
    }

    // MARK: - Schema reference

    func testSchemaReferenceSheet() {
        assertAppThemedSnapshots(
            of: CustomQuerySchemaReferenceView(),
            layout: .fixed(width: 390, height: 700)
        )
    }
}
