import Foundation

nonisolated extension AudioTuning {
    /// Builds the C-side VoiceBoostN configuration from the tuning snapshot.
    /// `initialGainDB` stays NAN here; precomputed loudness is seeded separately
    /// via `VBN_SetInitialGainDB`.
    func vbnConfig() -> VBNConfig {
        var config = VBN_GetDefaultConfig()

        config.targetLUFS = Float(voiceBoost.targetLUFS)
        config.maxGainDB = Float(voiceBoost.maxGainDB)
        config.minGainDB = Float(voiceBoost.minGainDB)
        config.gainSmoothingTauSeconds = Float(voiceBoost.gainSmoothingTauSeconds)
        config.adaptiveGainSmoothing = voiceBoost.adaptiveGainSmoothing

        config.hpEnabled = voiceBoost.hpEnabled
        config.hpFrequency = Float(voiceBoost.hpFrequency)
        config.hpQ = Float(voiceBoost.hpQ)

        config.compEnabled = voiceBoost.compEnabled
        config.compThresholdDB = Float(voiceBoost.compThresholdDB)
        config.compRatio = Float(voiceBoost.compRatio)
        config.compAttackMs = Float(voiceBoost.compAttackMs)
        config.compReleaseMs = Float(voiceBoost.compReleaseMs)
        config.compKneeWidthDB = Float(voiceBoost.compKneeWidthDB)

        config.limiterCeilingDB = Float(voiceBoost.limiterCeilingDB)
        config.limiterLookaheadMs = Float(voiceBoost.limiterLookaheadMs)
        config.limiterReleaseMs = Float(voiceBoost.limiterReleaseMs)
        config.truePeakEnabled = voiceBoost.truePeakEnabled

        return config
    }
}
