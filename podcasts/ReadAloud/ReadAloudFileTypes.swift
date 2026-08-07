import Foundation
import PocketCastsReadAloud
import PocketCastsUtils
import UniformTypeIdentifiers

/// The document types Read Aloud can import.
///
/// Deliberately its own list rather than an addition to
/// `FileTypeUtil.supportedUserFileTypes`: that type's `isSupportedUserFileType`
/// predicate is injected into the uploads folder scanner
/// (`FileSyncCoordinator`), so widening it would make the scanner mint
/// `UserEpisode` rows for any stray `.txt` sitting in the user's sync folder.
/// The picker's allowed types and the scanner's idea of a media file are two
/// different questions that happen to have shared an answer until now.
nonisolated enum ReadAloudFileTypes {
    /// Types offered in the document picker, when the feature is on.
    static var pickerTypes: [UTType] {
        TextExtractorRegistry.standard.supportedTypes
    }

    /// Whether a picked file should go to Read Aloud rather than the ordinary
    /// add-a-media-file flow. Extension first, then conformance, matching how the
    /// extractor registry resolves — Markdown's UTType is only as reliable as the
    /// declarations on the running device.
    static func isReadAloudDocument(url: URL) -> Bool {
        guard FeatureFlag.readAloud.enabled else { return false }
        return TextExtractorRegistry.standard.extractor(
            filename: url.lastPathComponent,
            type: UTType(filenameExtension: url.pathExtension)
        ) != nil
    }
}
