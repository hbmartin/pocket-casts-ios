import PocketCastsDataModel
import XCTest

@testable import podcasts

@MainActor
final class CustomPlaylistEditorViewModelTests: XCTestCase {
    // MARK: - Helpers

    private func makeViewModel(
        mode: CustomPlaylistEditorViewModel.Mode = .creation,
        draft: EpisodeFilter? = nil,
        validator: @escaping CustomPlaylistEditorViewModel.Validator = { _ in .failure(.empty) },
        smartRulesFragmentProvider: @escaping (EpisodeFilter) -> String = { _ in "" }
    ) -> CustomPlaylistEditorViewModel {
        var filter = draft ?? EpisodeFilter()
        if filter.uuid.isEmpty {
            filter.uuid = UUID().uuidString
            filter.playlistName = "Test Playlist"
        }
        return CustomPlaylistEditorViewModel(
            draft: filter,
            mode: mode,
            validator: validator,
            smartRulesFragmentProvider: smartRulesFragmentProvider,
            livePreviewEnabled: false
        )
    }

    private func firstCondition(of viewModel: CustomPlaylistEditorViewModel, inGroupID groupID: UUID? = nil) -> CustomQueryDraftCondition? {
        let group = groupID.flatMap { viewModel.document.group(withID: $0) } ?? viewModel.document
        for child in group.children {
            if case .condition(let condition) = child { return condition }
        }
        return nil
    }

    private func lastGroup(of group: CustomQueryDraftGroup) -> CustomQueryDraftGroup? {
        for child in group.children.reversed() {
            if case .group(let nested) = child { return nested }
        }
        return nil
    }

    // MARK: - AST editing ops

    func testAddConditionAppendsToRootGroup() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.document.totalConditionCount, 0)

        viewModel.addCondition(toGroupID: viewModel.document.id)

        XCTAssertEqual(viewModel.document.totalConditionCount, 1)
        XCTAssertEqual(firstCondition(of: viewModel)?.field, CustomQueryField.allCases.first)
        XCTAssertTrue(viewModel.hasChanges)
    }

    func testAddGroupNestsAndConditionsLandInside() {
        let viewModel = makeViewModel()

        viewModel.addGroup(toGroupID: viewModel.document.id)
        guard let nested = lastGroup(of: viewModel.document) else {
            XCTFail("Expected a nested group")
            return
        }

        viewModel.addCondition(toGroupID: nested.id)

        XCTAssertEqual(viewModel.document.totalConditionCount, 1)
        XCTAssertNotNil(firstCondition(of: viewModel, inGroupID: nested.id))
        XCTAssertEqual(viewModel.document.depth(ofGroupID: nested.id), 2)
    }

    func testDepthCapPreventsGroupsBeyondMaxDepth() {
        let viewModel = makeViewModel()

        viewModel.addGroup(toGroupID: viewModel.document.id)
        guard let depth2 = lastGroup(of: viewModel.document) else { XCTFail("missing depth-2 group")
return }

        viewModel.addGroup(toGroupID: depth2.id)
        guard let depth3 = viewModel.document.group(withID: depth2.id).flatMap(lastGroup(of:)) else {
            XCTFail("missing depth-3 group")
            return
        }
        XCTAssertEqual(viewModel.document.depth(ofGroupID: depth3.id), CustomQueryLimits.maxDepth)

        // At the cap: adding another level must be refused and leave the tree untouched.
        XCTAssertFalse(viewModel.canAddGroup(to: depth3))
        let before = viewModel.document
        viewModel.addGroup(toGroupID: depth3.id)
        XCTAssertEqual(viewModel.document, before)
    }

    func testChildrenPerGroupCapEnforced() {
        let viewModel = makeViewModel()

        for _ in 0..<CustomQueryLimits.maxChildrenPerGroup {
            viewModel.addCondition(toGroupID: viewModel.document.id)
        }
        XCTAssertEqual(viewModel.document.children.count, CustomQueryLimits.maxChildrenPerGroup)

        XCTAssertFalse(viewModel.canAddCondition(to: viewModel.document))
        XCTAssertFalse(viewModel.canAddGroup(to: viewModel.document))
        viewModel.addCondition(toGroupID: viewModel.document.id)
        viewModel.addGroup(toGroupID: viewModel.document.id)
        XCTAssertEqual(viewModel.document.children.count, CustomQueryLimits.maxChildrenPerGroup)
    }

    func testTotalConditionCapEnforcedAcrossGroups() {
        let viewModel = makeViewModel()

        // Two nested groups plus 18 root conditions, then fill the groups to 50 total.
        viewModel.addGroup(toGroupID: viewModel.document.id)
        viewModel.addGroup(toGroupID: viewModel.document.id)
        let groups = viewModel.document.children.compactMap { child -> CustomQueryDraftGroup? in
            if case .group(let group) = child { return group }
            return nil
        }
        XCTAssertEqual(groups.count, 2)

        for _ in 0..<18 {
            viewModel.addCondition(toGroupID: viewModel.document.id)
        }
        for _ in 0..<CustomQueryLimits.maxChildrenPerGroup {
            viewModel.addCondition(toGroupID: groups[0].id)
        }
        for _ in 0..<12 {
            viewModel.addCondition(toGroupID: groups[1].id)
        }
        XCTAssertEqual(viewModel.document.totalConditionCount, CustomQueryLimits.maxConditions)

        // The second group has spare child slots, but the document-wide cap wins.
        guard let groupB = viewModel.document.group(withID: groups[1].id) else { XCTFail("missing group")
return }
        XCTAssertLessThan(groupB.children.count, CustomQueryLimits.maxChildrenPerGroup)
        XCTAssertFalse(viewModel.canAddCondition(to: groupB))
        viewModel.addCondition(toGroupID: groupB.id)
        XCTAssertEqual(viewModel.document.totalConditionCount, CustomQueryLimits.maxConditions)
    }

    func testRemoveNodeDeletesNestedCondition() {
        let viewModel = makeViewModel()

        viewModel.addGroup(toGroupID: viewModel.document.id)
        guard let nested = lastGroup(of: viewModel.document) else { XCTFail("missing group")
return }
        viewModel.addCondition(toGroupID: nested.id)
        guard let condition = firstCondition(of: viewModel, inGroupID: nested.id) else { XCTFail("missing condition")
return }

        viewModel.removeNode(id: condition.id)
        XCTAssertEqual(viewModel.document.totalConditionCount, 0)

        viewModel.removeNode(id: nested.id)
        XCTAssertTrue(viewModel.document.children.isEmpty)
    }

    func testSetGroupMatchUpdatesNestedGroup() {
        let viewModel = makeViewModel()

        viewModel.addGroup(toGroupID: viewModel.document.id)
        guard let nested = lastGroup(of: viewModel.document) else { XCTFail("missing group")
return }
        XCTAssertEqual(nested.match, .any)

        viewModel.setGroupMatch(.all, groupID: nested.id)
        XCTAssertEqual(viewModel.document.group(withID: nested.id)?.match, .all)

        viewModel.setGroupMatch(.any, groupID: viewModel.document.id)
        XCTAssertEqual(viewModel.document.match, .any)
    }

    func testChangingFieldResetsOperatorAndValue() {
        let viewModel = makeViewModel()
        viewModel.addCondition(toGroupID: viewModel.document.id)
        guard var condition = firstCondition(of: viewModel) else { XCTFail("missing condition")
return }

        condition.value.text = "interview"
        viewModel.updateCondition(condition)

        let duration = CustomQueryField.duration
        viewModel.updateCondition(condition.changingField(to: duration))

        guard let updated = viewModel.condition(withID: condition.id) else { XCTFail("missing condition")
return }
        XCTAssertEqual(updated.field, .duration)
        XCTAssertEqual(updated.op, duration.allowedOperators.first)
        XCTAssertEqual(updated.value.text, "", "stale values must not survive a field change")
    }

    // MARK: - Builder save state

    func testBuilderSaveDisabledUntilConditionsComplete() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.canSave, "empty document isn't savable")
        XCTAssertNil(viewModel.envelopeForSaving())

        viewModel.addCondition(toGroupID: viewModel.document.id)
        XCTAssertFalse(viewModel.canSave, "a default text condition has no value yet")
        XCTAssertTrue(viewModel.builderHasIncompleteConditions)
        XCTAssertNil(viewModel.envelopeForSaving())

        guard var condition = firstCondition(of: viewModel) else { XCTFail("missing condition")
return }
        condition.value.text = "interview"
        viewModel.updateCondition(condition)

        XCTAssertTrue(viewModel.canSave)
        XCTAssertFalse(viewModel.builderHasIncompleteConditions)
        XCTAssertNotNil(viewModel.envelopeForSaving())
    }

    func testBuilderEnvelopeRoundTrips() throws {
        let viewModel = makeViewModel()
        viewModel.addCondition(toGroupID: viewModel.document.id)
        guard var condition = firstCondition(of: viewModel) else { XCTFail("missing condition")
return }
        condition.value.text = "interview"
        viewModel.updateCondition(condition)

        let envelope = try XCTUnwrap(viewModel.envelopeForSaving())
        let parsed = try XCTUnwrap(CustomPlaylistQuery(envelopeJSON: envelope))
        XCTAssertEqual(parsed.mode, .builder)
        XCTAssertNotNil(parsed.root)
    }

    // MARK: - SQL validation state machine

    func testValidateSuccessTransitionsToValidAndEnablesSave() async {
        let viewModel = makeViewModel(validator: { _ in .success(7) })
        viewModel.editorMode = .sql
        viewModel.sqlText = "episode.duration > 1800"
        XCTAssertEqual(viewModel.sqlValidation, .notValidated)
        XCTAssertFalse(viewModel.canSave)

        viewModel.validateSQL()
        await viewModel.validationTask?.value

        XCTAssertEqual(viewModel.sqlValidation, .valid(matchCount: 7))
        XCTAssertTrue(viewModel.canSave)
        XCTAssertNotNil(viewModel.envelopeForSaving())
    }

    func testValidateFailureShowsErrorAndKeepsSaveDisabled() async {
        let viewModel = makeViewModel(validator: { _ in .failure(.syntax(message: "boom")) })
        viewModel.editorMode = .sql
        viewModel.sqlText = "episode.duration >"

        viewModel.validateSQL()
        await viewModel.validationTask?.value

        XCTAssertEqual(viewModel.sqlValidation, .invalid(message: L10n.playlistCustomErrorSyntax("boom")))
        XCTAssertFalse(viewModel.canSave)
        XCTAssertNil(viewModel.envelopeForSaving())
    }

    func testEditingSQLTextResetsValidation() async {
        let viewModel = makeViewModel(validator: { _ in .success(3) })
        viewModel.editorMode = .sql
        viewModel.sqlText = "episode.duration > 1800"

        viewModel.validateSQL()
        await viewModel.validationTask?.value
        XCTAssertEqual(viewModel.sqlValidation, .valid(matchCount: 3))

        viewModel.sqlText = "episode.duration > 3600"
        XCTAssertEqual(viewModel.sqlValidation, .notValidated)
        XCTAssertFalse(viewModel.canSave)
    }

    func testStaleValidationResultIsDropped() async {
        let gate = ValidationGate()
        let viewModel = makeViewModel(validator: { _ in
            await gate.wait()
            return .success(99)
        })
        viewModel.editorMode = .sql
        viewModel.sqlText = "episode.duration > 1800"

        viewModel.validateSQL()
        XCTAssertEqual(viewModel.sqlValidation, .validating)

        // The user keeps typing while validation is in flight.
        viewModel.sqlText = "episode.duration > 60"
        XCTAssertEqual(viewModel.sqlValidation, .notValidated)

        await gate.open()
        await viewModel.validationTask?.value

        XCTAssertEqual(viewModel.sqlValidation, .notValidated, "a result for stale text must be ignored")
        XCTAssertFalse(viewModel.canSave)
    }

    // MARK: - Seeding

    func testSeedFromCurrentRulesPopulatesSQLText() {
        let fragment = "episode.playingStatus = 1 AND episode.archived = 0"
        let viewModel = makeViewModel(smartRulesFragmentProvider: { _ in fragment })
        viewModel.editorMode = .sql

        viewModel.seedFromCurrentRules()

        XCTAssertEqual(viewModel.sqlText, fragment)
        XCTAssertEqual(viewModel.sqlValidation, .notValidated, "seeded SQL still needs validating")
        XCTAssertFalse(viewModel.canSave)
    }

    // MARK: - Edit-mode loading

    func testEditModeLoadsExistingSQLQuery() throws {
        var filter = EpisodeFilter()
        filter.uuid = UUID().uuidString
        filter.playlistName = "Existing"
        filter.customQuery = try CustomPlaylistQuery(sql: "episode.duration > 1800").envelopeJSON()

        let viewModel = makeViewModel(mode: .edit, draft: filter)

        XCTAssertEqual(viewModel.editorMode, .sql)
        XCTAssertEqual(viewModel.sqlText, "episode.duration > 1800")
        XCTAssertFalse(viewModel.hasChanges, "loading isn't a user edit")
        XCTAssertEqual(viewModel.sqlValidation, .notValidated)
    }

    func testEditModeLoadsExistingBuilderQueryIntoDocument() throws {
        let root = CustomQueryNode.group(CustomQueryGroup(op: .any, children: [
            .condition(CustomQueryCondition(field: .duration, op: .greaterThan, value: .number(1800))),
            .condition(CustomQueryCondition(field: .episodeTitle, op: .contains, value: .string("interview")))
        ]))

        var filter = EpisodeFilter()
        filter.uuid = UUID().uuidString
        filter.playlistName = "Existing"
        filter.customQuery = try CustomPlaylistQuery(root: root).envelopeJSON()

        let viewModel = makeViewModel(mode: .edit, draft: filter)

        XCTAssertEqual(viewModel.editorMode, .builder)
        XCTAssertEqual(viewModel.document.match, .any)
        XCTAssertEqual(viewModel.document.totalConditionCount, 2)
        let condition = firstCondition(of: viewModel)
        XCTAssertEqual(condition?.field, .duration)
        XCTAssertEqual(condition?.op, .greaterThan)
        XCTAssertEqual(condition?.value.numberText, "1800")
        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertTrue(viewModel.canSave, "a complete loaded document is savable once edited")
    }

    // MARK: - Transcript predicate

    func testTranscriptConditionCompletenessRequiresSearchableText() {
        var condition = CustomQueryDraftCondition.makeDefault(for: .transcriptMentions)
        XCTAssertEqual(condition.op, .mentions)
        XCTAssertFalse(condition.isComplete, "empty term is incomplete")

        condition.value.text = "!!! ???"
        XCTAssertFalse(condition.isComplete, "punctuation-only sanitizes to nothing, so the compiler would reject it")

        condition.value.text = "climate change"
        XCTAssertTrue(condition.isComplete)
    }

    func testTranscriptFieldHasHonestFootnote() {
        XCTAssertNotNil(CustomQueryField.transcriptMentions.footnote)
        XCTAssertNil(CustomQueryField.duration.footnote)
    }

    func testUsesTranscriptFieldReflectsBuilderDocument() {
        let viewModel = makeViewModel()
        viewModel.addCondition(toGroupID: viewModel.document.id)
        XCTAssertFalse(viewModel.usesTranscriptField)

        guard var condition = firstCondition(of: viewModel) else {
            XCTFail("Expected a condition")
            return
        }
        condition = condition.changingField(to: .transcriptMentions)
        condition.value.text = "wwdc"
        viewModel.updateCondition(condition)

        XCTAssertTrue(viewModel.usesTranscriptField)
    }

    func testUsesTranscriptFieldSpotsTableNameInSQLMode() {
        let viewModel = makeViewModel()
        viewModel.editorMode = .sql
        viewModel.sqlText = "episode.duration > 1800"
        XCTAssertFalse(viewModel.usesTranscriptField)

        viewModel.sqlText = "episode.uuid IN (SELECT episodeUuid FROM transcriptsegmentindex WHERE transcriptsegmentindex MATCH '\"x\"')"
        XCTAssertTrue(viewModel.usesTranscriptField, "SQL mode falls back to a case-insensitive table-name check")
    }
}

/// Suspends a validator until the test releases it, so in-flight states can be asserted.
private actor ValidationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        // open() may run before the detached validator reaches wait(); parking
        // then would hang the suite for the full execution-time allowance.
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
