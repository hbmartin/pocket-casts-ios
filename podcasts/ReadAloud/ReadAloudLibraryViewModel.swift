import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud
import SwiftUI

/// Backs the library screen: every imported document with its narrations.
@MainActor
final class ReadAloudLibraryViewModel: ObservableObject {
    struct Entry: Identifiable {
        let document: ReadAloudDocumentRecord
        let narrations: [NarrationRecord]

        var id: String { document.uuid }
    }

    @Published private(set) var entries: [Entry] = []
    @Published var pendingDeletion: ReadAloudDocumentRecord?

    private let dataManager: DataManager
    private let importer: NarrationImporter
    /// Teardown lives in the box because a MainActor-isolated deinit can't read
    /// isolated state here; see ObservationTokenBox.
    private let tokenBox = ObservationTokenBox()

    init(dataManager: DataManager = .sharedManager, importer: NarrationImporter = NarrationImporter()) {
        self.dataManager = dataManager
        self.importer = importer
    }

    func start() {
        refresh()
        guard tokenBox.token == nil else { return }
        // One notification per rendered chunk, so this is the progress feed as
        // well as the state feed.
        tokenBox.token = NotificationCenter.default.addObserver(for: NarrationsChanged.self) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        entries = dataManager.readAloud.library().map { Entry(document: $0.document, narrations: $0.narrations) }
    }

    // MARK: - Actions

    func retry(_ narration: NarrationRecord) {
        Analytics.track(.readAloudNarrationRetried)
        Task {
            await NarrationQueue.shared.retry(uuid: narration.uuid)
            refresh()
        }
    }

    func cancel(_ narration: NarrationRecord) {
        Analytics.track(.readAloudNarrationCancelled)
        Task {
            await NarrationQueue.shared.cancel(uuid: narration.uuid)
            refresh()
        }
    }

    func delete(_ narration: NarrationRecord) {
        Analytics.track(.readAloudNarrationDeleted)
        importer.delete(narration: narration)
        refresh()
    }

    func confirmDelete(_ document: ReadAloudDocumentRecord) {
        Analytics.track(.readAloudDocumentDeleted, properties: [
            "narration_count": entries.first { $0.document.uuid == document.uuid }?.narrations.count ?? 0,
        ])
        importer.delete(document: document)
        pendingDeletion = nil
        refresh()
    }

    /// Total bytes of the retained source documents — the only Read Aloud
    /// storage the user can act on, since narration audio is ordinary episodes
    /// managed on the Files screen.
    func sourceStorageBytes(storage: ReadAloudStorage = .default) -> Int64 {
        entries.reduce(into: Int64(0)) { total, entry in
            let url = storage.sourceURL(relativePath: entry.document.sourcePath)
            total += (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) as? Int64 ?? 0
        }
    }
}

extension NarrationRecord {
    /// Fraction rendered, for the progress bar. Zero chunks means "not started",
    /// not "done".
    var progress: Double {
        guard chunkCount > 0 else { return 0 }
        return min(Double(completedChunkCount) / Double(chunkCount), 1)
    }

    var isActive: Bool {
        narrationState == .queued || narrationState == .rendering
    }
}
