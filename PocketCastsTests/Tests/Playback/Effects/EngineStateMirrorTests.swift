import PocketCastsDataModel
import XCTest

@testable import podcasts

final class EngineStateMirrorTests: XCTestCase {
    func testPublishedEffectsAreAnImmutableValueSnapshot() {
        let mirror = PlaybackManager.EngineStateMirror()
        let effects = PlaybackEffects()
        effects.playbackSpeed = 1.5
        effects.trimSilence = .medium
        effects.volumeBoost = true

        mirror.publish(effects: effects)
        effects.playbackSpeed = 3
        effects.trimSilence = .off
        effects.volumeBoost = false

        XCTAssertEqual(mirror.effects.playbackSpeed, 1.5)
        XCTAssertEqual(mirror.effects.trimSilence, .medium)
        XCTAssertTrue(mirror.effects.volumeBoost)
    }

    func testReliableMeterClearRemovesLastPublishedValue() {
        let mirror = PlaybackManager.EngineStateMirror()
        let meters = PlaybackManager.EngineStateMirror.VoiceBoostMeters(
            gainDB: 3,
            measuredLUFS: -17,
            limiterReductionDB: -1
        )

        XCTAssertTrue(mirror.publishVoiceBoostMeters(meters))
        XCTAssertEqual(mirror.voiceBoostMeters, meters)

        mirror.clearVoiceBoostMeters()

        XCTAssertNil(mirror.voiceBoostMeters)
    }
}
