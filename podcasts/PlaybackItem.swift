import AVFoundation
import PocketCastsDataModel
import PocketCastsServer

nonisolated class PlaybackItem: NSObject {
    var episode: BaseEpisode

    init(episode: BaseEpisode) {
        self.episode = episode
    }

    static func itemFromEpisode(_ episode: BaseEpisode) -> PlaybackItem? {
        PlaybackItem(episode: episode)
    }

    func createPlayerItem() -> AVPlayerItem? {
        guard let url = EpisodeManager.urlForEpisode(episode) else { return nil }
        // there is now an official, working way to set the user-agent for every request
        // https://developer.apple.com/documentation/avfoundation/avurlassethttpuseragentkey
        var options: [String: Any] = [AVURLAssetHTTPUserAgentKey: ServerConstants.Values.appUserAgent]
        // private local feeds: reattach the stored Basic credential, but only to same-origin
        // media URLs. The header-fields options key has no SDK constant, but is the
        // long-established key AVURLAsset honours for per-request HTTP headers.
        if let authorization = LocalFeedCredentials.mediaAuthorizationHeader(for: episode, mediaURL: url) {
            options["AVURLAssetHTTPHeaderFieldsKey"] = [ServerConstants.HttpHeaders.authorization: authorization]
        }
        let asset = AVURLAsset(url: url, options: options)
        return AVPlayerItem(asset: asset)
    }
}
