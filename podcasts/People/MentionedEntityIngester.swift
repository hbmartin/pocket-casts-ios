import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Feeds the Mentioned Entity substrate (Highlights S10) from its three
/// sources. Each ingest replaces that episode+source's rows whole, so
/// regenerated mentions or edited speaker names never accumulate stale rows.
/// All writes are flag-gated; ingestion is incremental — the catalog grows as
/// users view episodes and name speakers (a backfill sweep is not needed for
/// correctness, only coverage).
nonisolated enum MentionedEntityIngester {
    /// Transcript mentions, at generation/caching time.
    static func ingest(mentions: [EntityMention], episodeUuid: String, podcastUuid: String?) {
        guard FeatureFlag.mentionedEntityIndex.enabled else { return }
        let now = Date().timeIntervalSince1970
        let records = mentions.map { mention -> MentionedEntityRecord in
            var record = MentionedEntityRecord()
            record.kind = mention.kind.rawValue
            record.canonicalKey = mention.name.foldedEntityKey
            record.displayName = mention.name
            record.podcastUuid = podcastUuid
            record.startTime = mention.startTime
            record.createdAt = now
            return record
        }
        DataManager.sharedManager.mentionedEntities.replace(
            episodeUuid: episodeUuid, source: .mention, entities: records)
    }

    /// Feed credits (`<podcast:person>`), when episode metadata decodes.
    static func ingest(credits: [Episode.Metadata.Person], episodeUuid: String, podcastUuid: String?) {
        guard FeatureFlag.mentionedEntityIndex.enabled else { return }
        let now = Date().timeIntervalSince1970
        let records = credits.compactMap { person -> MentionedEntityRecord? in
            guard !person.name.foldedEntityKey.isEmpty else { return nil }
            var record = MentionedEntityRecord()
            record.kind = MentionedEntityKind.person.rawValue
            record.canonicalKey = person.name.foldedEntityKey
            record.displayName = person.name
            record.podcastUuid = podcastUuid
            record.role = person.role
            record.createdAt = now
            return record
        }
        DataManager.sharedManager.mentionedEntities.replace(
            episodeUuid: episodeUuid, source: .credit, entities: records)
    }

    /// Renamed transcript speakers, at rename-save time.
    static func ingest(speakerNames: [String], episodeUuid: String, podcastUuid: String?) {
        guard FeatureFlag.mentionedEntityIndex.enabled else { return }
        let now = Date().timeIntervalSince1970
        let records = speakerNames.compactMap { name -> MentionedEntityRecord? in
            guard !name.foldedEntityKey.isEmpty else { return nil }
            var record = MentionedEntityRecord()
            record.kind = MentionedEntityKind.person.rawValue
            record.canonicalKey = name.foldedEntityKey
            record.displayName = name
            record.podcastUuid = podcastUuid
            record.createdAt = now
            return record
        }
        DataManager.sharedManager.mentionedEntities.replace(
            episodeUuid: episodeUuid, source: .speaker, entities: records)
    }
}
