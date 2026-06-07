final class ProfileViewController {
    enum TableRow {
        case allStats
        case downloaded
        case starred
        case bookmarks
        case listeningHistory
        case help
        case uploadedFiles
    }

    private func refreshTableDataMissingUploadedFiles() {
        var data: [[TableRow]]
        // ruleid: pocketcasts.profile-uploaded-files-row-present
        data = [[.allStats, .downloaded, .starred, .bookmarks, .listeningHistory, .help]]
        _ = data
    }

    private func refreshTableDataWithUploadedFiles() {
        var data: [[TableRow]]
        // ok: pocketcasts.profile-uploaded-files-row-present
        data = [[.allStats, .downloaded, .starred, .bookmarks, .listeningHistory, .help, .uploadedFiles]]
        _ = data
    }
}
