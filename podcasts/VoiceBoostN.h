/**
 * VoiceBoostN - Podcast Audio Normalizer
 *
 * A high-quality audio normalization library optimized for spoken word content.
 * Implements ITU BS.1770-4 compliant LUFS measurement with adaptive gain control,
 * compression, and true-peak limiting.
 *
 * Target loudness: -14 LUFS (podcast standard)
 *
 * USAGE:
 *   #include "VoiceBoostN.h"
 *
 *   VBNState* vb = VBN_Create(48000.0);
 *   VBN_Process(vb, channels, frameCount, channelCount);
 *   float gain = VBN_GetCurrentGainDB(vb);
 *   VBN_Destroy(vb);
 *
 * REQUIREMENTS:
 *   - Apple Accelerate.framework
 */

#ifndef VOICEBOOSTN_H
#define VOICEBOOSTN_H

#include <Accelerate/Accelerate.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque state handle
typedef struct VBNState VBNState;

// ============================================================================
// Configuration
// ============================================================================

/**
 * Runtime-tunable processing parameters. VBN_GetDefaultConfig() reproduces the
 * historical hardcoded behavior exactly (hard knee, sample-peak limiting,
 * fixed ~0.5 s gain smoothing).
 */
typedef struct VBNConfig {
    // Loudness normalization
    float targetLUFS;              // pre-compressor target (compressor adds ~3 dB)
    float maxGainDB;
    float minGainDB;
    float gainSmoothingTauSeconds; // one-pole time constant for gain convergence
    bool adaptiveGainSmoothing;    // converge faster while far from target

    // High-pass filter
    bool hpEnabled;
    float hpFrequency;
    float hpQ;

    // Compressor
    bool compEnabled;
    float compThresholdDB;
    float compRatio;
    float compAttackMs;
    float compReleaseMs;
    float compKneeWidthDB;         // 0 = hard knee

    // Limiter
    float limiterCeilingDB;        // dBTP with oversampling on, dBFS sample-peak otherwise
    float limiterLookaheadMs;
    float limiterReleaseMs;
    bool truePeakEnabled;          // 4x oversampled inter-sample peak detection
                                   // (ITU-R BS.1770-4 Annex 2; ~48 MAC/sample/channel)

    // Seed gain for precomputed loudness; NAN = adapt from scratch
    float initialGainDB;
} VBNConfig;

/**
 * The default configuration, matching the historical hardcoded DSP.
 */
VBNConfig VBN_GetDefaultConfig(void);

/**
 * Stage a new configuration. Safe to call from any thread while another thread
 * is inside VBN_Process: the config is double-buffered and applied at the top
 * of the next VBN_Process call. Gain discontinuities are masked by per-sample
 * gain ramping.
 *
 * @param state Processor instance
 * @param config New configuration (copied)
 */
void VBN_SetConfig(VBNState* state, const VBNConfig* config);

/**
 * Read the currently staged configuration.
 */
void VBN_GetConfig(const VBNState* state, VBNConfig* outConfig);

/**
 * Seed the gain from a precomputed loudness measurement so playback starts at
 * the right level instead of adapting over the first few seconds. Call on the
 * creating thread right after VBN_CreateWithConfig.
 *
 * @param state Processor instance
 * @param gainDB Gain to apply immediately (clamped to the config's min/max)
 */
void VBN_SetInitialGainDB(VBNState* state, float gainDB);

// ============================================================================
// Lifecycle
// ============================================================================

/**
 * Create a new VoiceBoostN processor instance with the default configuration.
 *
 * @param sampleRate Audio sample rate in Hz (e.g., 44100, 48000)
 * @return New processor instance, or NULL on allocation failure
 */
VBNState* VBN_Create(double sampleRate);

/**
 * Create a new VoiceBoostN processor instance with a custom configuration.
 *
 * @param sampleRate Audio sample rate in Hz (e.g., 44100, 48000)
 * @param config Configuration to apply (NULL uses the default)
 * @return New processor instance, or NULL on allocation failure
 */
VBNState* VBN_CreateWithConfig(double sampleRate, const VBNConfig* config);

/**
 * Destroy a processor instance and free all resources.
 *
 * @param state Processor instance (NULL is safely ignored)
 */
void VBN_Destroy(VBNState* state);

/**
 * Reset processor to initial state.
 * Clears all filter states, gain history, and LUFS measurements.
 *
 * @param state Processor instance
 */
void VBN_Reset(VBNState* state);

// ============================================================================
// Processing
// ============================================================================

/**
 * Process audio through the full normalization chain.
 * Audio is processed in-place through:
 *   1. LUFS measurement (ITU BS.1770-4, per-channel K-weighted energy sum)
 *   2. Adaptive gain (default target: -17 LUFS pre-compressor)
 *   3. High-pass filter (default 80 Hz)
 *   4. Compression (default -8 dB threshold, 2:1 ratio)
 *   5. Peak limiting (default ceiling -2.0 dB; sample-peak unless
 *      truePeakEnabled turns on 4x oversampled inter-sample peak detection)
 *
 * @param state Processor instance
 * @param channels Array of pointers to channel sample buffers (modified in-place)
 * @param frameCount Number of samples per channel
 * @param channelCount Number of channels (1 = mono, 2 = stereo)
 */
void VBN_Process(VBNState* state,
                 float* const* channels,
                 int frameCount,
                 int channelCount);

// ============================================================================
// State Queries (for UI/metering)
// ============================================================================

/**
 * Get the current applied gain in dB.
 *
 * @param state Processor instance
 * @return Current gain in dB (positive = boost, negative = cut)
 */
float VBN_GetCurrentGainDB(const VBNState* state);

/**
 * Get the most recent LUFS measurement of input audio.
 *
 * @param state Processor instance
 * @return Measured loudness in LUFS
 */
float VBN_GetMeasuredLUFS(const VBNState* state);

/**
 * Get the current limiter gain reduction in dB.
 *
 * @param state Processor instance
 * @return Limiter reduction in dB (0 or negative when limiting)
 */
float VBN_GetLimiterReductionDB(const VBNState* state);

/**
 * Get the target loudness.
 *
 * @param state Processor instance
 * @return Target LUFS value (-14.0)
 */
float VBN_GetTargetLUFS(const VBNState* state);

#ifdef __cplusplus
}
#endif

#endif // VOICEBOOSTN_H
