import AVFoundation
import UIKit

class AVFileUtil: NSObject {
    private var durationHandler: (TimeInterval) -> Void
    private var titleHandler: (String?) -> Void
    private var artworkHandler: (UIImage?) -> Void
    private var url: URL
    private var asset: AVURLAsset
    private var metadataTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    static let min_artwork_size = 100

    init(fileURL: URL, durationHandler: @escaping ((TimeInterval) -> Void), titleHandler: @escaping ((String?) -> Void), artworkHandler: @escaping ((UIImage?) -> Void)) {
        url = fileURL
        asset = AVURLAsset(url: url)
        self.durationHandler = durationHandler
        self.artworkHandler = artworkHandler
        self.titleHandler = titleHandler

        super.init()

        loadMetaData()
    }

    deinit {
        cancelTasks()
    }

    func cancelLoading() {
        cancelTasks()
    }

    private func cancelTasks() {
        metadataTask?.cancel()
        durationTask?.cancel()
        metadataTask = nil
        durationTask = nil
    }

    func loadMetaData() {
        cancelLoading()

        metadataTask = Task { [weak self] in
            guard let asset = self?.asset, let titleHandler = self?.titleHandler, let artworkHandler = self?.artworkHandler else { return }
            let metadataItems: [AVMetadataItem]
            do {
                metadataItems = try await asset.load(.commonMetadata)
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                titleHandler(nil)
                artworkHandler(nil)
                return
            }

            do {
                try await AVFileUtil.processTitle(metadataItems: metadataItems, titleHandler: titleHandler)
                try Task.checkCancellation()
                try await AVFileUtil.processArtwork(metadataItems: metadataItems, artworkHandler: artworkHandler)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                titleHandler(nil)
                artworkHandler(nil)
            }
        }

        // Load duration separately as it can take longer than basic metadata.
        durationTask = Task { [weak self] in
            guard let asset = self?.asset, let durationHandler = self?.durationHandler else { return }
            do {
                let duration = try await asset.load(.duration)
                try Task.checkCancellation()
                durationHandler(CMTimeGetSeconds(duration))
            } catch {
                return
            }
        }
    }

    private static func processTitle(metadataItems: [AVMetadataItem], titleHandler: (String?) -> Void) async throws {
        try Task.checkCancellation()
        let titleMetaData = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .commonIdentifierTitle)

        if let metaData = titleMetaData.first {
            do {
                let title = try await metaData.load(.stringValue)
                try Task.checkCancellation()
                if let title, !title.isEmpty {
                    titleHandler(title)
                    return
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
            }
        }

        try Task.checkCancellation()
        titleHandler(nil)
    }

    private static func processArtwork(metadataItems: [AVMetadataItem], artworkHandler: (UIImage?) -> Void) async throws {
        try Task.checkCancellation()
        let artworks = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .commonIdentifierArtwork)
        var artworkImages = [UIImage]()

        for item in artworks {
            do {
                try Task.checkCancellation()
                let data = try await item.load(.dataValue)
                try Task.checkCancellation()
                if let data, SJMediaMetadataHelper.isValidEmbeddedImage(data), let image = UIImage(data: data) {
                    artworkImages.append(image)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
            }
        }

        try Task.checkCancellation()
        var biggestImage: UIImage?
        if artworkImages.isEmpty {
            artworkHandler(nil)
            return
        } else if artworkImages.count == 1 {
            biggestImage = artworkImages.first
        } else {
            for image in artworkImages {
                if biggestImage == nil {
                    biggestImage = image
                } else {
                    if image.size.height > (biggestImage?.size.height ?? 0) || image.size.width > (biggestImage?.size.width ?? 0) {
                        biggestImage = image
                    }
                }
            }
        }

        try Task.checkCancellation()
        if let biggest = biggestImage, biggest.size.width >= CGFloat(AVFileUtil.min_artwork_size) {
            artworkHandler(biggest)
        } else {
            artworkHandler(nil)
        }
    }
}
