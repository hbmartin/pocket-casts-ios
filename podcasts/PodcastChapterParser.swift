import AVFoundation
import Foundation
import PocketCastsServer
import PocketCastsUtils
import PocketCastsDataModel
import UIKit

/// @unchecked Sendable: stateless; unchecked (rather than plain Sendable) because the class stays non-final for test mocks.
nonisolated class PodcastChapterParser: @unchecked Sendable {
    func parseLocalFile(_ path: String, episodeDuration: TimeInterval, completion: @escaping @Sendable ([ChapterInfo]) -> Void) {
        parseChapters(url: URL(fileURLWithPath: path), episodeDuration: episodeDuration, completion: completion)
    }

    func parseRemoteFile(_ remoteUrl: String, episodeDuration: TimeInterval, completion: @escaping @Sendable ([ChapterInfo]) -> Void) {
        guard let url = URL(string: remoteUrl) else { return }

        parseChapters(url: url, episodeDuration: episodeDuration, completion: completion)
    }

    func parseLocalFile(_ path: String, episodeDuration: TimeInterval) async -> [ChapterInfo] {
        // The parsed chapters are freshly built by parseChapters and handed over
        // wholesale, so boxing them across the continuation is safe
        let boxed: PocketCastsUtils.UncheckedSendable<[ChapterInfo]> = await withCheckedContinuation { continuation in
            parseChapters(url: URL(fileURLWithPath: path), episodeDuration: episodeDuration) {
                continuation.resume(returning: PocketCastsUtils.UncheckedSendable($0))
            }
        }
        return boxed.value
    }

    func parseRemoteFile(_ remoteUrl: String, episodeDuration: TimeInterval) async -> [ChapterInfo] {
        let boxed: PocketCastsUtils.UncheckedSendable<[ChapterInfo]> = await withCheckedContinuation { continuation in
            guard let url = URL(string: remoteUrl) else {
                continuation.resume(returning: PocketCastsUtils.UncheckedSendable([]))
                return
            }

            parseChapters(url: url, episodeDuration: episodeDuration) {
                continuation.resume(returning: PocketCastsUtils.UncheckedSendable($0))
            }
        }
        return boxed.value
    }

    func parsePodloveChapters(_ podloveChapters: [Episode.Metadata.EpisodeChapter], episodeDuration: TimeInterval) -> [ChapterInfo] {
        podloveChapters.enumerated().compactMap { index, chapter in
            let chapterInfo = ChapterInfo()
            chapterInfo.title = chapter.title ?? ""
            chapterInfo.index = index
            chapterInfo.startTime = CMTime(seconds: chapter.startTime, preferredTimescale: 1000000)
            if Self.isValidUrl(chapter.url) {
                chapterInfo.url = chapter.url
            }

            // Calculate chapter duration based on the info we have
            if let endTime = chapter.endTime {
                chapterInfo.duration = endTime - chapter.startTime
            } else if let nextChapterStartTime = podloveChapters[safe: index + 1]?.startTime {
                chapterInfo.duration = nextChapterStartTime - chapter.startTime
            } else {
                chapterInfo.duration = episodeDuration - chapter.startTime
            }

            return chapterInfo
        }
    }

    func parsePodcastIndexChapters(_ podcastIndexChapters: [PodcastIndexChapter], episodeDuration: TimeInterval) -> [ChapterInfo] {
        podcastIndexChapters.enumerated().map { index, chapter in
            let chapterInfo = ChapterInfo()
            chapterInfo.title = chapter.title ?? ""
            chapterInfo.index = chapter.number ?? index
            chapterInfo.startTime = CMTime(seconds: chapter.startTime, preferredTimescale: 1000000)
            if Self.isValidUrl(chapter.url) {
                chapterInfo.url = chapter.url
            }
            if let endTime = chapter.endTime {
                chapterInfo.duration = endTime - chapter.startTime
            } else if let nextChapterStartTime = podcastIndexChapters[safe: index + 1]?.startTime {
                chapterInfo.duration = nextChapterStartTime - chapter.startTime
            } else {
                chapterInfo.duration = episodeDuration - chapter.startTime
            }
            return chapterInfo
        }
    }

    func parseGeneratedChapters(_ generatedChapters: [GeneratedChapter], episodeDuration: TimeInterval) -> [ChapterInfo] {
        let sortedChapters = generatedChapters.sorted { $0.startTime < $1.startTime }

        return sortedChapters.enumerated().map { index, chapter in
            let chapterInfo = ChapterInfo()
            chapterInfo.title = chapter.title
            chapterInfo.index = index
            chapterInfo.startTime = CMTime(seconds: chapter.startTime, preferredTimescale: 1000000)
            if let nextChapterStartTime = sortedChapters[safe: index + 1]?.startTime {
                chapterInfo.duration = nextChapterStartTime - chapter.startTime
            } else {
                chapterInfo.duration = episodeDuration - chapter.startTime
            }
            return chapterInfo
        }
    }

    private func parseChapters(url: URL, episodeDuration: TimeInterval, completion: @escaping @Sendable ([ChapterInfo]) -> Void) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else {
                completion([])
                return
            }

            completion(await self.parseEmbeddedChapters(at: url))
        }
    }

    /// Extracts embedded chapters: ID3v2 CHAP/CTOC frames for MP3-style files (recognised by their
    /// leading ID3 tag), MP4 chapter tracks for everything else.
    private func parseEmbeddedChapters(at url: URL) async -> [ChapterInfo] {
        if let tagData = await loadLeadingID3Tag(from: url) {
            return convertID3Chapters(ID3ChapterParser.parseChapters(from: tagData))
        }

        return await parseMP4Chapters(at: url)
    }

    // MARK: - ID3 (MP3)

    /// Ceiling on how much of a file we're willing to buffer for a declared ID3 tag; chapter-heavy
    /// tags with per-chapter artwork run to a few MB, so anything past this is treated as corrupt.
    private static let maxID3TagLength = 64 * 1024 * 1024

    /// Returns the file's leading ID3v2 tag bytes (header included), or nil when the file doesn't
    /// start with one. Only the tag's declared length is read, never the whole file.
    private func loadLeadingID3Tag(from url: URL) async -> Data? {
        url.isFileURL ? loadLocalID3Tag(from: url) : await loadRemoteID3Tag(from: url)
    }

    private func loadLocalID3Tag(from url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: ID3ChapterParser.tagHeaderLength),
              let tagLength = ID3ChapterParser.declaredTagLength(fromHeader: header),
              tagLength <= Self.maxID3TagLength,
              (try? handle.seek(toOffset: 0)) != nil
        else { return nil }

        return try? handle.read(upToCount: tagLength)
    }

    private func loadRemoteID3Tag(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(ServerConstants.Values.appUserAgent, forHTTPHeaderField: ServerConstants.HttpHeaders.userAgent)
        guard let (byteStream, response) = try? await URLSession.shared.bytes(for: request),
              let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode)
        else { return nil }

        var data = Data()
        var tagLength: Int?
        do {
            for try await byte in byteStream {
                data.append(byte)
                if tagLength == nil, data.count == ID3ChapterParser.tagHeaderLength {
                    guard let declaredLength = ID3ChapterParser.declaredTagLength(fromHeader: data),
                          declaredLength <= Self.maxID3TagLength
                    else { return nil } // not an ID3-tagged file (or an absurd tag): stop the download
                    tagLength = declaredLength
                    data.reserveCapacity(declaredLength)
                }
                if let tagLength, data.count >= tagLength { break }
            }
        } catch {
            // Connection dropped mid-tag: fall through, the parser copes with truncated tags
            FileLog.shared.addMessage("Embedded chapter fetch interrupted for \(url): \(error)")
        }

        return tagLength != nil ? data : nil
    }

    private func convertID3Chapters(_ id3Chapters: [ID3Chapter]) -> [ChapterInfo] {
        guard !id3Chapters.isEmpty else { return [] }

        // If the table of contents hid every chapter, ignore it and show them all
        let unhideAll = id3Chapters.allSatisfy(\.isHidden)

        var parsedChapters = [ChapterInfo]()
        var index = 0
        for chapter in id3Chapters {
            let convertedChapter = ChapterInfo()
            convertedChapter.title = chapter.title ?? ""
            convertedChapter.image = chapter.artworkData.flatMap { UIImage(data: $0) }
            convertedChapter.startTime = CMTime(value: CMTimeValue(chapter.startTimeMs), timescale: 1000)
            convertedChapter.duration = (Double(chapter.endTimeMs) - Double(chapter.startTimeMs)) / 1000
            convertedChapter.isHidden = unhideAll ? false : chapter.isHidden
            if !convertedChapter.isHidden {
                convertedChapter.index = index
                index += 1
            }
            if Self.isValidUrl(chapter.url) {
                convertedChapter.url = chapter.url
            }

            parsedChapters.append(convertedChapter)
        }
        parsedChapters.first(where: { !$0.isHidden })?.isFirst = true
        parsedChapters.last(where: { !$0.isHidden })?.isLast = true
        return parsedChapters
    }

    // MARK: - MP4 chapter tracks

    private func parseMP4Chapters(at url: URL) async -> [ChapterInfo] {
        let customHeaders = [ServerConstants.HttpHeaders.userAgent: ServerConstants.Values.appUserAgent]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": customHeaders])

        var languages = Locale.preferredLanguages
        if let chapterLocales = try? await asset.load(.availableChapterLocales) {
            languages.append(contentsOf: chapterLocales.map(\.identifier))
        }
        guard let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages), !groups.isEmpty else {
            return []
        }

        var parsedChapters = [ChapterInfo]()
        for (index, group) in groups.enumerated() {
            let chapter = ChapterInfo()
            chapter.index = index
            chapter.startTime = group.timeRange.start
            chapter.duration = group.timeRange.duration.seconds

            if let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first {
                chapter.title = (try? await titleItem.load(.stringValue)) ?? ""
                if let extraAttributes = try? await titleItem.load(.extraAttributes),
                   let href = extraAttributes[AVMetadataExtraAttributeKey(rawValue: "HREF")] as? String,
                   Self.isValidUrl(href) {
                    chapter.url = href
                }
            }
            if let artworkItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierArtwork).first,
               let artworkData = try? await artworkItem.load(.dataValue) {
                chapter.image = UIImage(data: artworkData)
            }

            parsedChapters.append(chapter)
        }
        parsedChapters.first?.isFirst = true
        parsedChapters.last?.isLast = true
        return parsedChapters
    }

    /// Shared link validation for every chapter source (embedded ID3/MP4,
    /// Podlove metadata, Podcast Index): only http(s) URLs reach the chapter
    /// link UI. Static so it stays pure logic, testable without a parser.
    static func isValidUrl(_ urlStr: String?) -> Bool {
        // first check can we actually make a URL out of this string and does it have a scheme?
        guard let urlStr, let url = URL(string: urlStr), let scheme = url.scheme else { return false }

        // next see if the scheme is http or https, we don't support any others
        return scheme.caseInsensitiveCompare("http") == .orderedSame || scheme.caseInsensitiveCompare("https") == .orderedSame
    }
}
