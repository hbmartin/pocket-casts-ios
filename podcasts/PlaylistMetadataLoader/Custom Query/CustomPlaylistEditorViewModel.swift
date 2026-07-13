import Combine
import Foundation
import PocketCastsDataModel

/// Drives the custom playlist editor: the Builder/SQL mode switch, the builder's
/// AST document (with the engine's caps enforced at edit time), the SQL
/// validation state machine, and a debounced live preview of matching episodes.
@MainActor
final class CustomPlaylistEditorViewModel: ObservableObject {
    enum Mode {
        case creation
        case edit
    }

    enum EditorMode: String, CaseIterable, Identifiable {
        case builder
        case sql

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .builder: L10n.playlistCustomModeBuilder
            case .sql: L10n.playlistCustomModeSql
            }
        }
    }

    enum SQLValidationState: Equatable {
        /// Nothing validated yet (or the text changed since the last run). Save stays disabled.
        case notValidated
        case validating
        case valid(matchCount: Int)
        case invalid(message: String)
    }

    typealias Validator = @Sendable (String) async -> Result<Int, CustomQueryValidationError>

    let mode: Mode

    /// The draft filter being edited. Smart-rule fields ride along untouched;
    /// the envelope only lands in `customQuery` at save/preview time.
    @Published var draft: EpisodeFilter

    @Published var editorMode: EditorMode = .builder {
        didSet {
            guard editorMode != oldValue else { return }
            if editorMode == .builder {
                schedulePreview()
            }
        }
    }

    @Published private(set) var document = CustomQueryDraftGroup()

    @Published var sqlText: String = "" {
        didSet {
            guard sqlText != oldValue else { return }
            sqlValidation = .notValidated
            hasChanges = true
        }
    }

    @Published private(set) var sqlValidation: SQLValidationState = .notValidated
    @Published private(set) var previewEpisodes = [ListEpisode]()
    @Published private(set) var previewMatchCount: Int?
    @Published private(set) var hasChanges = false

    /// Exposed for tests to await the in-flight validation.
    private(set) var validationTask: Task<Void, Never>?

    private let validator: Validator
    private let smartRulesFragmentProvider: (EpisodeFilter) -> String
    /// Snapshot/unit-test hosts disable the preview so the editor never touches the database.
    private let livePreviewEnabled: Bool

    private let previewDebounce = Debounce(delay: 0.3)
    private var previewCountTask: Task<Void, Never>?
    private lazy var previewQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(
        draft: EpisodeFilter,
        mode: Mode,
        validator: @escaping Validator = CustomPlaylistEditorViewModel.defaultValidator,
        smartRulesFragmentProvider: @escaping (EpisodeFilter) -> String = { PlaylistQueryBuilder.smartRulesFragment(for: $0) },
        livePreviewEnabled: Bool = true
    ) {
        self.draft = draft
        self.mode = mode
        self.validator = validator
        self.smartRulesFragmentProvider = smartRulesFragmentProvider
        self.livePreviewEnabled = livePreviewEnabled

        loadExistingQuery()
    }

    /// Runs `DataManager.validateCustomQueryFragment` off the main actor: the
    /// validator trial-executes the fragment against the database.
    static let defaultValidator: Validator = { sql in
        await Task.detached(priority: .userInitiated) {
            DataManager.sharedManager.validateCustomQueryFragment(sql)
        }.value
    }

    private func loadExistingQuery() {
        guard mode == .edit, let query = CustomPlaylistQuery(envelopeJSON: draft.customQuery) else { return }

        switch query.mode {
        case .builder:
            if let root = query.root {
                document = CustomQueryDraftGroup(node: root)
            }
            editorMode = .builder
        case .sql:
            sqlText = query.sql ?? ""
            editorMode = .sql
        }
        // Loading isn't a user edit.
        hasChanges = false
        sqlValidation = .notValidated
        schedulePreview()
    }

    // MARK: - Save state

    var canSave: Bool {
        switch editorMode {
        case .builder:
            return builderIsSavable
        case .sql:
            if case .valid = sqlValidation { return true }
            return false
        }
    }

    private var builderIsSavable: Bool {
        document.totalConditionCount > 0 && document.allConditionsComplete
    }

    /// True when at least one condition exists but some rows still need a value —
    /// drives the inline "fill in every condition" warning.
    var builderHasIncompleteConditions: Bool {
        document.totalConditionCount > 0 && !document.allConditionsComplete
    }

    /// The versioned envelope to persist, or nil when the current state can't be saved.
    func envelopeForSaving() -> String? {
        switch editorMode {
        case .builder:
            guard let root = document.queryNode() else { return nil }
            return try? CustomPlaylistQuery(root: root).envelopeJSON()
        case .sql:
            guard case .valid = sqlValidation else { return nil }
            return try? CustomPlaylistQuery(sql: sqlText.trimmingCharacters(in: .whitespacesAndNewlines)).envelopeJSON()
        }
    }

    // MARK: - Builder document edits

    func canAddCondition(to group: CustomQueryDraftGroup) -> Bool {
        group.children.count < CustomQueryLimits.maxChildrenPerGroup
            && document.totalConditionCount < CustomQueryLimits.maxConditions
    }

    func canAddGroup(to group: CustomQueryDraftGroup) -> Bool {
        guard let depth = document.depth(ofGroupID: group.id) else { return false }
        return depth < CustomQueryLimits.maxDepth
            && group.children.count < CustomQueryLimits.maxChildrenPerGroup
    }

    func addCondition(toGroupID groupID: UUID) {
        guard let group = document.group(withID: groupID), canAddCondition(to: group),
              let defaultField = CustomQueryField.allCases.first
        else { return }

        document.append(.condition(.makeDefault(for: defaultField)), toGroupID: groupID)
        documentEdited()
    }

    func addGroup(toGroupID groupID: UUID) {
        guard let group = document.group(withID: groupID), canAddGroup(to: group) else { return }

        document.append(.group(CustomQueryDraftGroup(match: .any)), toGroupID: groupID)
        documentEdited()
    }

    func removeNode(id nodeID: UUID) {
        guard document.removeNode(id: nodeID) else { return }
        documentEdited()
    }

    func updateCondition(_ condition: CustomQueryDraftCondition) {
        guard document.updateCondition(condition) else { return }
        documentEdited()
    }

    func setGroupMatch(_ match: CustomQueryDraftGroup.Match, groupID: UUID) {
        guard document.setMatch(match, forGroupID: groupID) else { return }
        documentEdited()
    }

    func condition(withID conditionID: UUID) -> CustomQueryDraftCondition? {
        document.condition(withID: conditionID)
    }

    private func documentEdited() {
        hasChanges = true
        schedulePreview()
    }

    // MARK: - SQL validation state machine

    func validateSQL() {
        let sql = sqlText
        sqlValidation = .validating
        validationTask?.cancel()
        validationTask = Task { [validator] in
            let result = await validator(sql)
            guard !Task.isCancelled, sql == self.sqlText else { return }

            self.applyValidationResult(result)

            let resultName: String
            switch result {
            case .success: resultName = "valid"
            case .failure(let error): resultName = error.analyticsName
            }
            Analytics.track(.filterCustomQueryValidated, properties: [
                "result": resultName,
                "mode": self.editorMode.rawValue
            ])
        }
    }

    /// Applies a validation outcome to the state machine. Split from
    /// `validateSQL()` so tests and snapshot fixtures can drive states directly.
    func applyValidationResult(_ result: Result<Int, CustomQueryValidationError>) {
        switch result {
        case .success(let matchCount):
            sqlValidation = .valid(matchCount: matchCount)
        case .failure(let error):
            sqlValidation = .invalid(message: error.displayMessage)
        }
    }

    /// Pre-fills the SQL editor from the draft's current smart-rule fields
    /// ("start from current rules"). The result still needs validating.
    func seedFromCurrentRules() {
        sqlText = smartRulesFragmentProvider(draft)
    }

    // MARK: - Live preview

    private func schedulePreview() {
        guard livePreviewEnabled else { return }
        previewDebounce.call { [weak self] in
            self?.reloadPreview()
        }
    }

    private func reloadPreview() {
        guard editorMode == .builder else { return }

        guard let root = document.queryNode(),
              let envelope = try? CustomPlaylistQuery(root: root).envelopeJSON()
        else {
            applyPreview(episodes: [], matchCount: nil)
            return
        }

        var filter = draft
        filter.customQuery = envelope

        previewQueue.cancelAllOperations()
        let refreshOperation = PlaylistRefreshOperation(playlist: filter) { [weak self] episodes in
            self?.previewEpisodes = episodes
        }
        previewQueue.addOperation(refreshOperation)

        previewCountTask?.cancel()
        // Immutable copy: a sending closure may not capture the mutated local var.
        let previewFilter = filter
        previewCountTask = Task {
            let count = await Task.detached(priority: .userInitiated) {
                DataManager.sharedManager.playlistEpisodeCount(for: previewFilter, episodeUuidToAdd: nil)
            }.value
            guard !Task.isCancelled else { return }
            self.previewMatchCount = count
        }
    }

    /// Directly applies preview data; used by the load path and test fixtures.
    func applyPreview(episodes: [ListEpisode], matchCount: Int?) {
        previewEpisodes = episodes
        previewMatchCount = matchCount
    }
}
