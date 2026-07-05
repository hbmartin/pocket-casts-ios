import Foundation

public protocol FilePathProtocol: AnyObject {
    func tempPathForEpisode(_ episode: BaseEpisode) -> String
    func pathForEpisode(_ episode: BaseEpisode) -> String
    func streamingBufferPathForEpisode(_ episode: BaseEpisode) -> String
}
