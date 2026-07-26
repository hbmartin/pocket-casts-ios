import PocketCastsServer
import XCTest

@testable import podcasts

@MainActor
final class SocialNotificationSettingsViewModelTests: XCTestCase {
    func testRapidTogglesSerializeAndPersistLatestMask() async {
        let gate = ProfileUpdateGate()
        let profile = SocialProfile(userId: "user", handle: "handle", displayName: "Name")
        let model = SocialNotificationSettingsViewModel(
            profile: profile,
            updateProfile: { await gate.update($0) }
        )

        model.set(.followRequest, enabled: false)
        await gate.waitForCallCount(1)
        model.set(.newFollower, enabled: false)
        let blockedRequestCount = await gate.pendingRequestCount
        XCTAssertEqual(blockedRequestCount, 1, "a second write must remain coalesced while the first is blocked")

        await gate.releaseNext()
        await gate.waitForCallCount(2)
        await gate.releaseNext()
        await model.waitForPendingSave()

        let expected = SocialPushType.setEnabled(
            .newFollower,
            enabled: false,
            in: SocialPushType.setEnabled(.followRequest, enabled: false, in: 0)
        )
        XCTAssertEqual(model.disabledMask, expected)
        let maximumConcurrentCalls = await gate.maximumConcurrentCalls
        let requestedMasks = await gate.requestedMasks
        XCTAssertEqual(maximumConcurrentCalls, 1)
        XCTAssertEqual(requestedMasks, [
            SocialPushType.setEnabled(.followRequest, enabled: false, in: 0),
            expected
        ])
    }

    func testFailedSaveRollsBackToConfirmedMask() async {
        let profile = SocialProfile(userId: "user", handle: "handle", displayName: "Name")
        let model = SocialNotificationSettingsViewModel(profile: profile, updateProfile: { _ in nil })

        model.set(.followRequest, enabled: false)
        await model.waitForPendingSave()

        XCTAssertEqual(model.disabledMask, profile.socialPushDisabled)
        XCTAssertNotNil(model.saveError)
    }
}

private actor ProfileUpdateGate {
    private var calls: [SocialProfile] = []
    private var pending: [(SocialProfile, CheckedContinuation<SocialProfile?, Never>)] = []
    private var callCountWaiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var activeCalls = 0
    private(set) var maximumConcurrentCalls = 0

    var pendingRequestCount: Int { pending.count }
    var requestedMasks: [Int64] { calls.map(\.socialPushDisabled) }

    func update(_ profile: SocialProfile) async -> SocialProfile? {
        calls.append(profile)
        let satisfiedWaiters = callCountWaiters.filter { calls.count >= $0.expected }
        callCountWaiters.removeAll { calls.count >= $0.expected }
        satisfiedWaiters.forEach { $0.continuation.resume() }
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
        let result = await withCheckedContinuation { pending.append((profile, $0)) }
        activeCalls -= 1
        return result
    }

    func waitForCallCount(_ expected: Int) async {
        guard calls.count < expected else { return }

        await withCheckedContinuation { continuation in
            callCountWaiters.append((expected, continuation))
        }
    }

    func releaseNext() {
        guard !pending.isEmpty else { return }
        let (profile, continuation) = pending.removeFirst()
        continuation.resume(returning: profile)
    }
}
