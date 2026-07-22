import PocketCastsServer
import XCTest
@testable import podcasts

@MainActor
final class SendToFriendViewModelTests: XCTestCase {
    func testNoteIsCappedAtServerLimit() {
        let model = makeModel()

        model.note = String(repeating: "a", count: SendToFriendViewModel.maximumNoteLength + 25)

        XCTAssertEqual(model.note.count, SendToFriendViewModel.maximumNoteLength)
    }

    func testLookupDoesNotRetainViewModelAcrossRequest() async {
        let gate = ProfileLookupGate()
        var model: SendToFriendViewModel? = makeModel(
            fetchPublicProfile: { handle in await gate.fetch(handle: handle) },
            lookupDelayNanoseconds: 0
        )
        weak var weakModel = model

        model?.handleInput = "recipient"
        await gate.waitUntilEntered()
        model = nil

        XCTAssertNil(weakModel)
        gate.release()
    }

    private func makeModel(
        fetchPublicProfile: @escaping SendToFriendViewModel.FetchPublicProfile = { _ in nil },
        lookupDelayNanoseconds: UInt64 = 350_000_000
    ) -> SendToFriendViewModel {
        SendToFriendViewModel(
            episodeUuid: "episode",
            podcastUuid: "podcast",
            episodeTitle: "Episode",
            podcastTitle: "Podcast",
            timestampSeconds: 0,
            fetchPublicProfile: fetchPublicProfile,
            lookupDelayNanoseconds: lookupDelayNanoseconds
        )
    }
}

@MainActor
private final class ProfileLookupGate {
    private var entered = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func fetch(handle: String) async -> SocialPublicProfile? {
        entered = true
        enteredContinuations.forEach { $0.resume() }
        enteredContinuations.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
        return nil
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredContinuations.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
