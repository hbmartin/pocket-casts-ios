import PocketCastsDataModel
import SwiftUI

/// Settings → Advanced Audio: exposes the full DSP tuning surface (trim
/// silence gate, Voice Boost normalization chain, time stretch) for advanced
/// users. Changes apply live to the running player.
struct AdvancedAudioSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @State private var model = AdvancedAudioSettingsViewModel()

    var body: some View {
        List {
            LiveStatusSection(model: model)
            TrimSilenceSection(model: model)
            VoiceBoostSection(model: model)
            DynamicsSection(model: model)
            TimeStretchSection(model: model)
            GlobalResetSection(model: model)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .onAppear { model.startMeterPolling() }
        .onDisappear {
            model.stopMeterPolling()
            model.flush() // commit any edit still inside the debounce window
        }
    }
}

// MARK: - Live status

private struct LiveStatusSection: View {
    @EnvironmentObject private var theme: Theme
    @Bindable var model: AdvancedAudioSettingsViewModel

    var body: some View {
        Section(header: header(L10n.advancedAudioMetersHeader)) {
            if let meters = model.meters, model.isPlaying {
                TuningMeterRow(title: L10n.advancedAudioMetersGain, value: String(format: "%+.1f dB", meters.gainDB))
                TuningMeterRow(title: L10n.advancedAudioMetersLufs, value: String(format: "%.1f LUFS", meters.measuredLUFS))
                TuningMeterRow(title: L10n.advancedAudioMetersLimiter, value: String(format: "%.1f dB", meters.limiterReductionDB))
            } else {
                Text(L10n.advancedAudioMetersIdle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
    }
}

// MARK: - Trim silence

private struct TrimSilenceSection: View {
    @EnvironmentObject private var theme: Theme
    @Bindable var model: AdvancedAudioSettingsViewModel

    var body: some View {
        Section(
            header: Text(L10n.advancedAudioTrimHeader).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.advancedAudioTrimCustomFooter).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            TuningToggleRow(title: L10n.advancedAudioTrimCustomToggle, isOn: $model.tuning.trim.useCustomGate)

            Menu {
                Button(L10n.playbackEffectTrimSilenceMild) { model.loadTrimPreset(.low) }
                Button(L10n.playbackEffectTrimSilenceMedium) { model.loadTrimPreset(.medium) }
                Button(L10n.playbackEffectTrimSilenceMax) { model.loadTrimPreset(.high) }
            } label: {
                Text(L10n.advancedAudioTrimLoadPreset)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.color(for: .primaryInteractive01, theme: theme))
            }

            Group {
                TuningPickerRow(
                    title: L10n.advancedAudioTrimDiscriminator,
                    options: [
                        (TrimDiscriminator.rms, L10n.advancedAudioTrimDiscriminatorRms),
                        (TrimDiscriminator.heuristic, L10n.advancedAudioTrimDiscriminatorHeuristic),
                        (TrimDiscriminator.vad, L10n.advancedAudioTrimDiscriminatorVad)
                    ],
                    selection: $model.tuning.trim.discriminator
                )
                TuningSliderRow(title: L10n.advancedAudioTrimThreshold, range: TrimTuning.thresholdDBRange, step: 0.5, unit: "dB", value: $model.tuning.trim.thresholdDB)
                TuningToggleRow(title: L10n.advancedAudioTrimAdaptiveFloor, isOn: $model.tuning.trim.adaptiveNoiseFloor)
                if model.tuning.trim.adaptiveNoiseFloor {
                    TuningSliderRow(title: L10n.advancedAudioTrimAdaptiveOffset, range: TrimTuning.adaptiveOffsetDBRange, step: 1, unit: "dB", fractionDigits: 0, value: $model.tuning.trim.adaptiveOffsetDB)
                    TuningSliderRow(title: L10n.advancedAudioTrimAdaptiveWindow, range: TrimTuning.adaptiveWindowSecondsRange, step: 1, unit: "s", fractionDigits: 0, value: $model.tuning.trim.adaptiveWindowSeconds)
                }
                TuningSliderRow(title: L10n.advancedAudioTrimHysteresis, range: TrimTuning.hysteresisDBRange, step: 0.5, unit: "dB", value: $model.tuning.trim.hysteresisDB)
                TuningSliderRow(title: L10n.advancedAudioTrimHold, range: TrimTuning.holdTimeMsRange, step: 10, unit: "ms", fractionDigits: 0, value: $model.tuning.trim.holdTimeMs)
                TuningSliderRow(title: L10n.advancedAudioTrimMinGap, range: TrimTuning.minGapMsRange, step: 25, unit: "ms", fractionDigits: 0, value: $model.tuning.trim.minGapMs)
                TuningSliderRow(title: L10n.advancedAudioTrimKeepGap, range: TrimTuning.keepGapMsRange, step: 25, unit: "ms", fractionDigits: 0, value: $model.tuning.trim.keepGapMs)
                TuningSliderRow(title: L10n.advancedAudioTrimCrossfade, range: TrimTuning.crossfadeMsRange, step: 5, unit: "ms", fractionDigits: 0, value: $model.tuning.trim.crossfadeMs)
                TuningSliderRow(title: L10n.advancedAudioTrimEndGuard, range: TrimTuning.endGuardSecondsRange, step: 1, unit: "s", fractionDigits: 0, value: $model.tuning.trim.endGuardSeconds)
            }
            .disabled(!model.tuning.trim.useCustomGate)
            .opacity(model.tuning.trim.useCustomGate ? 1 : 0.5)

            if model.tuning.trim.useCustomGate, model.tuning.trim.discriminator != .rms {
                TuningSliderRow(title: L10n.advancedAudioTrimFlatnessThreshold, range: TrimTuning.flatnessThresholdRange, step: 0.05, fractionDigits: 2, value: $model.tuning.trim.flatnessThreshold)
                TuningSliderRow(title: L10n.advancedAudioTrimZcrThreshold, range: TrimTuning.zcrThresholdRange, step: 0.01, fractionDigits: 2, value: $model.tuning.trim.zcrThreshold)
                TuningSliderRow(title: L10n.advancedAudioTrimZcrMargin, range: TrimTuning.zcrLevelMarginDBRange, step: 0.5, unit: "dB", value: $model.tuning.trim.zcrLevelMarginDB)
            }
            if model.tuning.trim.useCustomGate, model.tuning.trim.discriminator == .vad {
                TuningSliderRow(title: L10n.advancedAudioTrimVadConfidence, range: TrimTuning.vadSpeechConfidenceThresholdRange, step: 0.05, fractionDigits: 2, value: $model.tuning.trim.vadSpeechConfidenceThreshold)
            }

            TuningResetButton(title: L10n.advancedAudioResetSection) { model.resetTrimSilence() }
        }
    }
}

// MARK: - Voice Boost (normalization)

private struct VoiceBoostSection: View {
    @EnvironmentObject private var theme: Theme
    @Bindable var model: AdvancedAudioSettingsViewModel

    var body: some View {
        Section(
            header: Text(L10n.advancedAudioBoostHeader).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(footerText).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            TuningPickerRow(
                title: L10n.advancedAudioBoostEngine,
                options: [
                    (true, L10n.advancedAudioBoostEngineModern),
                    (false, L10n.advancedAudioBoostEngineLegacy)
                ],
                selection: $model.tuning.voiceBoost.useVoiceBoostN
            )

            Group {
                TuningSliderRow(title: L10n.advancedAudioBoostTargetLufs, range: VoiceBoostTuning.targetLUFSRange, step: 0.5, unit: "LUFS", value: $model.tuning.voiceBoost.targetLUFS)
                TuningSliderRow(title: L10n.advancedAudioBoostMaxGain, range: VoiceBoostTuning.maxGainDBRange, step: 1, unit: "dB", fractionDigits: 0, value: $model.tuning.voiceBoost.maxGainDB)
                TuningSliderRow(title: L10n.advancedAudioBoostMinGain, range: VoiceBoostTuning.minGainDBRange, step: 1, unit: "dB", fractionDigits: 0, value: $model.tuning.voiceBoost.minGainDB)
                TuningSliderRow(title: L10n.advancedAudioBoostGainSmoothing, range: VoiceBoostTuning.gainSmoothingTauSecondsRange, step: 0.05, unit: "s", fractionDigits: 2, value: $model.tuning.voiceBoost.gainSmoothingTauSeconds)
                TuningToggleRow(title: L10n.advancedAudioBoostAdaptiveSmoothing, isOn: $model.tuning.voiceBoost.adaptiveGainSmoothing)
                TuningToggleRow(title: L10n.advancedAudioBoostHighPass, isOn: $model.tuning.voiceBoost.hpEnabled)
                if model.tuning.voiceBoost.hpEnabled {
                    TuningSliderRow(title: L10n.advancedAudioBoostHighPassFreq, range: VoiceBoostTuning.hpFrequencyRange, step: 5, unit: "Hz", fractionDigits: 0, value: $model.tuning.voiceBoost.hpFrequency)
                    TuningSliderRow(title: L10n.advancedAudioBoostHighPassQ, range: VoiceBoostTuning.hpQRange, step: 0.01, fractionDigits: 2, value: $model.tuning.voiceBoost.hpQ)
                }
            }
            .disabled(!model.tuning.voiceBoost.useVoiceBoostN)
            .opacity(model.tuning.voiceBoost.useVoiceBoostN ? 1 : 0.5)
        }
    }

    private var footerText: String {
        model.voiceBoostNFlagEnabled ? L10n.advancedAudioBoostTargetLufsFooter : L10n.advancedAudioBoostEngineFooter
    }
}

// MARK: - Voice Boost (compressor and limiter)

private struct DynamicsSection: View {
    @EnvironmentObject private var theme: Theme
    @Bindable var model: AdvancedAudioSettingsViewModel

    var body: some View {
        Section(
            header: Text(L10n.advancedAudioBoostDynamicsHeader).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.advancedAudioBoostTruePeakFooter).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            Group {
                TuningToggleRow(title: L10n.advancedAudioBoostCompressor, isOn: $model.tuning.voiceBoost.compEnabled)
                if model.tuning.voiceBoost.compEnabled {
                    TuningSliderRow(title: L10n.advancedAudioBoostCompThreshold, range: VoiceBoostTuning.compThresholdDBRange, step: 0.5, unit: "dB", value: $model.tuning.voiceBoost.compThresholdDB)
                    TuningSliderRow(title: L10n.advancedAudioBoostCompRatio, range: VoiceBoostTuning.compRatioRange, step: 0.1, unit: ":1", value: $model.tuning.voiceBoost.compRatio)
                    TuningSliderRow(title: L10n.advancedAudioBoostCompAttack, range: VoiceBoostTuning.compAttackMsRange, step: 1, unit: "ms", fractionDigits: 0, value: $model.tuning.voiceBoost.compAttackMs)
                    TuningSliderRow(title: L10n.advancedAudioBoostCompRelease, range: VoiceBoostTuning.compReleaseMsRange, step: 10, unit: "ms", fractionDigits: 0, value: $model.tuning.voiceBoost.compReleaseMs)
                    TuningSliderRow(title: L10n.advancedAudioBoostCompKnee, range: VoiceBoostTuning.compKneeWidthDBRange, step: 0.5, unit: "dB", value: $model.tuning.voiceBoost.compKneeWidthDB)
                }
                TuningSliderRow(title: L10n.advancedAudioBoostLimiterCeiling, range: VoiceBoostTuning.limiterCeilingDBRange, step: 0.1, unit: "dB", value: $model.tuning.voiceBoost.limiterCeilingDB)
                TuningSliderRow(title: L10n.advancedAudioBoostLimiterLookahead, range: VoiceBoostTuning.limiterLookaheadMsRange, step: 0.5, unit: "ms", value: $model.tuning.voiceBoost.limiterLookaheadMs)
                TuningSliderRow(title: L10n.advancedAudioBoostLimiterRelease, range: VoiceBoostTuning.limiterReleaseMsRange, step: 10, unit: "ms", fractionDigits: 0, value: $model.tuning.voiceBoost.limiterReleaseMs)
                TuningToggleRow(title: L10n.advancedAudioBoostTruePeak, isOn: $model.tuning.voiceBoost.truePeakEnabled)
            }
            .disabled(!model.tuning.voiceBoost.useVoiceBoostN)
            .opacity(model.tuning.voiceBoost.useVoiceBoostN ? 1 : 0.5)

            TuningResetButton(title: L10n.advancedAudioResetSection) { model.resetVoiceBoost() }
        }
    }
}

// MARK: - Time stretch

private struct TimeStretchSection: View {
    @EnvironmentObject private var theme: Theme
    @Bindable var model: AdvancedAudioSettingsViewModel

    var body: some View {
        Section(
            header: Text(L10n.advancedAudioStretchHeader).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.advancedAudioStretchFooter).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            TuningPickerRow(
                title: L10n.advancedAudioStretchEffectsPlayer,
                options: [
                    (TimeStretchTuning.EffectsPlayerAlgorithm.iPodTimeOther, L10n.advancedAudioStretchAlgoIpod),
                    (TimeStretchTuning.EffectsPlayerAlgorithm.spectral, L10n.advancedAudioStretchAlgoSpectral)
                ],
                selection: $model.tuning.timeStretch.effectsPlayerAlgorithm
            )
            TuningPickerRow(
                title: L10n.advancedAudioStretchDefaultPlayer,
                options: [
                    (TimeStretchTuning.DefaultPlayerAlgorithm.timeDomain, L10n.advancedAudioStretchAlgoTimeDomain),
                    (TimeStretchTuning.DefaultPlayerAlgorithm.spectral, L10n.advancedAudioStretchAlgoSpectral),
                    (TimeStretchTuning.DefaultPlayerAlgorithm.varispeed, L10n.advancedAudioStretchAlgoVarispeed)
                ],
                selection: $model.tuning.timeStretch.defaultPlayerAlgorithm
            )
            TuningResetButton(title: L10n.advancedAudioResetSection) { model.resetTimeStretch() }
        }
    }
}

// MARK: - Global reset

private struct GlobalResetSection: View {
    @EnvironmentObject private var theme: Theme
    @Bindable var model: AdvancedAudioSettingsViewModel

    var body: some View {
        Section(footer: Text(L10n.advancedAudioFooterWarning).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))) {
            TuningResetButton(title: L10n.advancedAudioResetAll) { model.showingResetConfirmation = true }
        }
        .alert(L10n.advancedAudioResetConfirmTitle, isPresented: $model.showingResetConfirmation) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.advancedAudioResetAll, role: .destructive) { model.resetAll() }
        } message: {
            Text(L10n.advancedAudioResetConfirmMessage)
        }
    }
}
