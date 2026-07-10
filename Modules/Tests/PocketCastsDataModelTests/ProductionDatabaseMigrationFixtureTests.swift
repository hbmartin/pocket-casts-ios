import Foundation
import GRDB
@testable import PocketCastsDataModel
import Testing

@Suite("Production database migration fixtures", .tags(.integration, .databaseMigration))
struct ProductionDatabaseMigrationFixtureTests {
    @Test("Version 73 library data survives migration to the current schema")
    func version73LibrarySurvivesMigration() throws {
        let sandbox = try ParallelTestDatabaseSandbox()
        defer { try? sandbox.cleanUp() }

        #expect(DatabaseHelper.setup(queue: sandbox.databaseQueue, migrations: []))

        let fixtureURL = try #require(
            Bundle.module.url(forResource: "Fixtures/ProductionDatabases/v73.sql", withExtension: nil)
                ?? Bundle.module.url(
                    forResource: "v73",
                    withExtension: "sql",
                    subdirectory: "Fixtures/ProductionDatabases"
                )
        )
        let fixtureSQL = try String(contentsOf: fixtureURL, encoding: .utf8)
        try sandbox.databasePool.write { database in
            try database.execute(sql: fixtureSQL)
        }

        #expect(DatabaseHelper.setup(queue: sandbox.databaseQueue))

        let dataManager = DataManager(dbQueue: sandbox.databaseQueue)
        let podcast = try #require(
            dataManager.findPodcast(uuid: "fixture-podcast", includeUnsubscribed: true)
        )
        let episode = try #require(dataManager.findEpisode(uuid: "fixture-episode"))
        let userEpisode = try #require(dataManager.findUserEpisode(uuid: "fixture-user-episode"))

        #expect(podcast.title == "Fixture & Friends")
        #expect(podcast.folderUuid == "fixture-folder")
        #expect(!podcast.isExplicit)
        #expect(episode.title == "An Episode Worth Keeping")
        #expect(episode.playedUpTo == 321.5)
        #expect(dataManager.allUpNextEpisodes().map(\.uuid) == ["fixture-episode"])
        #expect(userEpisode.title == "A Local File")
        #expect(userEpisode.folderRelativePath == nil)
        #expect(userEpisode.contentHash == nil)
        #expect(userEpisode.identity == .legacyLocal)

        try sandbox.databasePool.read { database in
            let schemaVersion = try Int.fetchOne(database, sql: "PRAGMA user_version")
            let journalCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM FileSyncJournal")
            let cursorCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM FileSyncCursor")

            #expect(
                schemaVersion
                    == Int(DatabaseHelper.currentSchemaVersion(for: DatabaseHelper.migrations))
            )
            #expect(journalCount == 0)
            #expect(cursorCount == 0)
        }
    }
}

extension Tag {
    @Tag static var integration: Self
    @Tag static var databaseMigration: Self
}
