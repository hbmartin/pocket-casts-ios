/**
 * VoiceBoostN Internal Header
 *
 * This header exposes the internal state structure for use by the analysis module.
 * DO NOT include this header in external projects - use VoiceBoostN.h instead.
 */

#ifndef VOICEBOOSTN_INTERNAL_H
#define VOICEBOOSTN_INTERNAL_H

#include "VoiceBoostN.h"
#include <stdatomic.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration for analysis stats (defined in VoiceBoostNAnalysis.h)
typedef struct VBNStats VBNStats;

// Default constants (see VBN_GetDefaultConfig; runtime values live in VBNConfig)
#define VBN_TARGET_LUFS -17.0f  // Pre-compressor target; compressor adds ~3dB → final output ~-14 LUFS
#define VBN_MAX_GAIN_DB 24.0f
#define VBN_MIN_GAIN_DB -12.0f
#define VBN_BLOCK_DURATION 0.4        // 400ms blocks per ITU BS.1770-4
#define VBN_BLOCK_OVERLAP 0.75        // 75% overlap (100ms hop)
#define VBN_MAX_BLOCKS 30             // 3 seconds history for short-term LUFS (10 blocks/sec)
#define VBN_ABSOLUTE_THRESHOLD -70.0f   // ITU BS.1770-4 absolute gate
#define VBN_RELATIVE_THRESHOLD -10.0f   // ITU BS.1770-4 relative gate (LU below ungated)
// Default gain-convergence time constant. Matches the historical fixed one-pole
// (0.95/0.05 per 1152-frame buffer at 44.1 kHz ≈ 0.5 s).
#define VBN_GAIN_SMOOTH_TAU_SECONDS 0.5f
// Adaptive gain smoothing time constants (seconds), enabled via
// VBNConfig.adaptiveGainSmoothing. Derived from the historical per-buffer
// coefficients 0.70/0.80/0.90/0.97 at 1152 frames / 44.1 kHz.
#define VBN_GAIN_SMOOTH_TAU_FAST   0.073f  // > 10 dB error
#define VBN_GAIN_SMOOTH_TAU_MEDIUM 0.117f  // 5-10 dB error
#define VBN_GAIN_SMOOTH_TAU_SLOW   0.248f  // 2-5 dB error
#define VBN_GAIN_SMOOTH_TAU_STABLE 0.857f  // < 2 dB error (near target)

#define VBN_LIMITER_CEILING_DB -2.0f  // balanced headroom; sample-peak by default
#define VBN_LIMITER_LOOKAHEAD_MS 5.0
#define VBN_LIMITER_RELEASE_MS 100.0
#define VBN_DEQUE_CAPACITY 1024
#define VBN_TRUE_PEAK_PHASES 4        // 4x oversampling (ITU-R BS.1770-4 Annex 2)
#define VBN_TRUE_PEAK_TAPS 12         // taps per polyphase branch

#define VBN_HP_FREQUENCY 80.0
#define VBN_HP_Q 0.707

#define VBN_COMP_THRESHOLD_DB -8.0f
#define VBN_COMP_RATIO 2.0f
#define VBN_COMP_ATTACK_MS 100.0
#define VBN_COMP_RELEASE_MS 400.0
#define VBN_COMP_KNEE_WIDTH_DB 0.0f    // Soft knee width in dB (0 = hard knee, the historical behavior)

// Shared K-weighting coefficient calculation (ITU BS.1770-4), used by both the
// realtime processor and the offline loudness meter.
// preOut/rlbOut receive {b0, b1, b2, a1, a2}.
void VBN_ComputeKWeightingCoeffs(double sampleRate, double preOut[5], double rlbOut[5]);

// Internal state structure
struct VBNState {
    double sampleRate;

    // Configuration. `config` is the working copy read by the DSP; new configs
    // are staged into the inactive slot from any thread and swapped in at the
    // top of VBN_Process (single-writer/single-reader double buffer).
    VBNConfig config;
    VBNConfig configSlots[2];
    _Atomic int publishedSlot;
    _Atomic uint32_t configEpoch;
    uint32_t appliedEpoch;

    // LUFS measurement. sampleBuffer holds per-sample K-weighted squared
    // energy summed across channels (BS.1770-4 multichannel).
    float* sampleBuffer;
    int bufferSize;
    int bufferMask;
    int writeIndex;
    int samplesAccumulated;
    int blockSize;
    int hopSize;

    float preFilterDelays[2][4];
    float rlbFilterDelays[2][4];
    vDSP_biquad_Setup preFilterSetup;
    vDSP_biquad_Setup rlbFilterSetup;

    float blockLoudnesses[VBN_MAX_BLOCKS];
    int blockCount;
    float currentLUFS;
    float currentGain;
    float targetGain;
    float lastAppliedGain;  // per-sample ramp start for click-free gain changes
    bool hasInitialMeasurement;

    // High-pass filter
    float hpDelays[2][4];
    vDSP_biquad_Setup hpSetup;

    // Compressor
    float compThreshold;      // linear knee-independent threshold
    float compSlope;
    float compAttackCoef;
    float compReleaseCoef;
    float compKneeLowLinear;  // linear level where the knee region starts
    float compEnvelopes[2];

    // Limiter
    float limiterCeilingLinear;
    float limiterGain;
    float limiterReleaseCoef;
    int lookaheadSamples;
    int* dequeIndices;
    float* dequeValues;
    int dequeHead;
    int dequeTail;
    float* peakBuffer;
    float* gainBuffer;
    int maxLimiterBufferSize;

    // True-peak detection history (previous input samples per channel)
    float truePeakHistory[2][VBN_TRUE_PEAK_TAPS];

    // Work buffers for LUFS (per-channel K-weighting scratch + energy sum)
    float* tempBuffer;
    int tempBufferSize;
    float* energyBuffer;
    int energyBufferSize;

    // Gain ramp scratch
    float* gainRamp;
    int gainRampSize;

    // Analysis mode (only used when analysis module is linked)
    bool analysisEnabled;
    VBNStats* stats;  // Pointer to analysis stats (allocated by analysis module)

    // Temporary storage for before-processing measurements (used by analysis)
    float lastBeforeRMS;
    float lastBeforePeak;
    float lastBeforeTruePeak;
};

#ifdef __cplusplus
}
#endif

#endif // VOICEBOOSTN_INTERNAL_H
