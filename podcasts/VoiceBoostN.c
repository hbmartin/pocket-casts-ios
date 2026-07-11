/**
 * VoiceBoostN Core Implementation
 *
 * This file contains the core audio processing algorithms:
 * - ITU BS.1770-4 LUFS measurement (per-channel K-weighted energy sum)
 * - Adaptive gain control with per-sample click-free ramping
 * - High-pass filter
 * - Dynamic range compression (hard or soft knee)
 * - Peak limiting (sample-peak, or 4x oversampled true-peak per
 *   ITU-R BS.1770-4 Annex 2 when enabled)
 *
 * All parameters are runtime-configurable through VBNConfig; the default
 * config reproduces the original hardcoded behavior.
 */

#include "VoiceBoostN_Internal.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Forward declarations for internal functions
static void createLUFSFilterSetups(VBNState* state);
static void applyConfig(VBNState* state, const VBNConfig* config);
static void applyStagedConfigIfNeeded(VBNState* state);
static void processLUFS(VBNState* restrict state, float* const* restrict channels, int frameCount, int channelCount);
static void applyHighPass(VBNState* restrict state, float* restrict samples, int frameCount, int channel);
static void applyCompression(VBNState* restrict state, float* restrict samples, int frameCount, int channel);
static void applyLimiter(VBNState* restrict state, float* const* restrict channels, int frameCount, int channelCount);
static void measureBlock(VBNState* state);
static void computeTruePeakMagnitudes(VBNState* restrict state, int channel, const float* restrict samples, float* restrict outPeaks, int frameCount);

// ============================================================================
// Deque Operations (for sliding maximum in limiter)
// ============================================================================

static inline bool dequeIsEmpty(const VBNState* state) {
    return state->dequeHead == state->dequeTail;
}

static inline void dequeClear(VBNState* state) {
    state->dequeHead = 0;
    state->dequeTail = 0;
}

static inline void dequePushBack(VBNState* state, int idx, float val) {
    state->dequeIndices[state->dequeTail] = idx;
    state->dequeValues[state->dequeTail] = val;
    state->dequeTail = (state->dequeTail + 1) & (VBN_DEQUE_CAPACITY - 1);
}

static inline void dequePopBack(VBNState* state) {
    state->dequeTail = (state->dequeTail - 1 + VBN_DEQUE_CAPACITY) & (VBN_DEQUE_CAPACITY - 1);
}

static inline void dequePopFront(VBNState* state) {
    state->dequeHead = (state->dequeHead + 1) & (VBN_DEQUE_CAPACITY - 1);
}

static inline int dequeFrontIdx(const VBNState* state) {
    return state->dequeIndices[state->dequeHead];
}

static inline float dequeFrontVal(const VBNState* state) {
    return state->dequeValues[state->dequeHead];
}

static inline float dequeBackVal(const VBNState* state) {
    int back = (state->dequeTail - 1 + VBN_DEQUE_CAPACITY) & (VBN_DEQUE_CAPACITY - 1);
    return state->dequeValues[back];
}

// ============================================================================
// Configuration
// ============================================================================

VBNConfig VBN_GetDefaultConfig(void) {
    VBNConfig config;
    memset(&config, 0, sizeof(config));

    config.targetLUFS = VBN_TARGET_LUFS;
    config.maxGainDB = VBN_MAX_GAIN_DB;
    config.minGainDB = VBN_MIN_GAIN_DB;
    config.gainSmoothingTauSeconds = VBN_GAIN_SMOOTH_TAU_SECONDS;
    config.adaptiveGainSmoothing = false;

    config.hpEnabled = true;
    config.hpFrequency = (float)VBN_HP_FREQUENCY;
    config.hpQ = (float)VBN_HP_Q;

    config.compEnabled = true;
    config.compThresholdDB = VBN_COMP_THRESHOLD_DB;
    config.compRatio = VBN_COMP_RATIO;
    config.compAttackMs = (float)VBN_COMP_ATTACK_MS;
    config.compReleaseMs = (float)VBN_COMP_RELEASE_MS;
    config.compKneeWidthDB = VBN_COMP_KNEE_WIDTH_DB;

    config.limiterCeilingDB = VBN_LIMITER_CEILING_DB;
    config.limiterLookaheadMs = (float)VBN_LIMITER_LOOKAHEAD_MS;
    config.limiterReleaseMs = (float)VBN_LIMITER_RELEASE_MS;
    config.truePeakEnabled = false;

    config.initialGainDB = NAN;

    return config;
}

static float clampf(float value, float lo, float hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}

// Derives all runtime DSP values from `config`. Runs on the processing thread
// (at create time or at the top of VBN_Process after VBN_SetConfig). The biquad
// rebuild allocates; config changes are rare (UI-debounced), so this stays off
// the per-buffer hot path.
static void applyConfig(VBNState* state, const VBNConfig* config) {
    const VBNConfig old = state->config;
    state->config = *config;
    double sampleRate = state->sampleRate;

    // High-pass filter (rebuild only when its parameters changed)
    if (!state->hpSetup || old.hpFrequency != config->hpFrequency || old.hpQ != config->hpQ) {
        if (state->hpSetup) vDSP_biquad_DestroySetup(state->hpSetup);

        double w0 = 2.0 * M_PI * config->hpFrequency / sampleRate;
        double cosw0 = cos(w0);
        double sinw0 = sin(w0);
        double alpha = sinw0 / (2.0 * config->hpQ);

        double b0 = (1.0 + cosw0) / 2.0;
        double b1 = -(1.0 + cosw0);
        double b2 = (1.0 + cosw0) / 2.0;
        double a0 = 1.0 + alpha;
        double a1 = -2.0 * cosw0;
        double a2 = 1.0 - alpha;

        double coeffs[5] = { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 };
        state->hpSetup = vDSP_biquad_CreateSetup(coeffs, 1);
        memset(state->hpDelays, 0, sizeof(state->hpDelays));
    }

    // Compressor
    state->compThreshold = powf(10.0f, config->compThresholdDB / 20.0f);
    float ratio = fmaxf(config->compRatio, 1.0f);
    state->compSlope = 1.0f - 1.0f / ratio;
    double attackSamples = sampleRate * fmax(config->compAttackMs, 0.1f) / 1000.0;
    double releaseSamples = sampleRate * fmax(config->compReleaseMs, 1.0f) / 1000.0;
    state->compAttackCoef = (float)exp(-1.0 / attackSamples);
    state->compReleaseCoef = (float)exp(-1.0 / releaseSamples);
    state->compKneeLowLinear = powf(10.0f, (config->compThresholdDB - config->compKneeWidthDB * 0.5f) / 20.0f);

    // Limiter
    state->limiterCeilingLinear = powf(10.0f, config->limiterCeilingDB / 20.0f);
    int lookahead = (int)(sampleRate * config->limiterLookaheadMs / 1000.0);
    if (lookahead < 1) lookahead = 1;
    if (lookahead > VBN_DEQUE_CAPACITY - 1) lookahead = VBN_DEQUE_CAPACITY - 1;
    state->lookaheadSamples = lookahead;
    double limiterReleaseSamples = sampleRate * fmax(config->limiterReleaseMs, 1.0f) / 1000.0;
    state->limiterReleaseCoef = 1.0f - (float)exp(-2.2 / limiterReleaseSamples);
    if (old.truePeakEnabled != config->truePeakEnabled) {
        memset(state->truePeakHistory, 0, sizeof(state->truePeakHistory));
    }

    // Gain clamps
    float minGain = powf(10.0f, config->minGainDB / 20.0f);
    float maxGain = powf(10.0f, config->maxGainDB / 20.0f);
    state->targetGain = clampf(state->targetGain, minGain, maxGain);
    state->currentGain = clampf(state->currentGain, minGain, maxGain);
}

void VBN_SetConfig(VBNState* state, const VBNConfig* config) {
    if (!state || !config) return;

    // Single-writer double buffer: fill the slot the reader isn't using, then
    // publish it. The reader copies the published slot at the top of the next
    // VBN_Process call.
    int inactive = 1 - atomic_load_explicit(&state->publishedSlot, memory_order_relaxed);
    state->configSlots[inactive] = *config;
    atomic_store_explicit(&state->publishedSlot, inactive, memory_order_release);
    atomic_fetch_add_explicit(&state->configEpoch, 1, memory_order_release);
}

void VBN_GetConfig(const VBNState* state, VBNConfig* outConfig) {
    if (!state || !outConfig) return;
    int slot = atomic_load_explicit(&state->publishedSlot, memory_order_acquire);
    *outConfig = state->configSlots[slot];
}

void VBN_SetInitialGainDB(VBNState* state, float gainDB) {
    if (!state || isnan(gainDB)) return;

    float clamped = clampf(gainDB, state->config.minGainDB, state->config.maxGainDB);
    float gain = powf(10.0f, clamped / 20.0f);
    state->currentGain = gain;
    state->targetGain = gain;
    state->lastAppliedGain = gain;
    state->hasInitialMeasurement = true;
}

static void applyStagedConfigIfNeeded(VBNState* state) {
    uint32_t epoch = atomic_load_explicit(&state->configEpoch, memory_order_acquire);
    if (epoch == state->appliedEpoch) return;

    state->appliedEpoch = epoch;
    int slot = atomic_load_explicit(&state->publishedSlot, memory_order_acquire);
    VBNConfig staged = state->configSlots[slot];
    applyConfig(state, &staged);
}

// ============================================================================
// Lifecycle
// ============================================================================

VBNState* VBN_Create(double sampleRate) {
    return VBN_CreateWithConfig(sampleRate, NULL);
}

VBNState* VBN_CreateWithConfig(double sampleRate, const VBNConfig* config) {
    VBNState* state = (VBNState*)calloc(1, sizeof(VBNState));
    if (!state) return NULL;

    state->sampleRate = sampleRate;

    VBNConfig initialConfig = config ? *config : VBN_GetDefaultConfig();
    state->configSlots[0] = initialConfig;
    state->configSlots[1] = initialConfig;

    // LUFS setup
    state->blockSize = (int)(sampleRate * VBN_BLOCK_DURATION);
    state->hopSize = (int)(sampleRate * VBN_BLOCK_DURATION * (1.0 - VBN_BLOCK_OVERLAP));

    // Power-of-2 buffer for fast modulo
    int minSize = state->blockSize * 2;
    state->bufferSize = 1;
    while (state->bufferSize < minSize) state->bufferSize <<= 1;
    state->bufferMask = state->bufferSize - 1;

    state->sampleBuffer = (float*)calloc(state->bufferSize, sizeof(float));
    state->currentLUFS = -24.0f;
    state->currentGain = 1.0f;
    state->targetGain = 1.0f;
    state->lastAppliedGain = 1.0f;

    // K-weighting filters are config-independent
    createLUFSFilterSetups(state);

    // Derive the runtime DSP values from the config
    applyConfig(state, &initialConfig);

    // Limiter
    state->limiterGain = 1.0f;
    state->dequeIndices = (int*)calloc(VBN_DEQUE_CAPACITY, sizeof(int));
    state->dequeValues = (float*)calloc(VBN_DEQUE_CAPACITY, sizeof(float));

    if (!isnan(initialConfig.initialGainDB)) {
        VBN_SetInitialGainDB(state, initialConfig.initialGainDB);
    }

    return state;
}

void VBN_Destroy(VBNState* state) {
    if (!state) return;

    free(state->sampleBuffer);
    free(state->tempBuffer);
    free(state->energyBuffer);
    free(state->gainRamp);
    free(state->dequeIndices);
    free(state->dequeValues);
    free(state->peakBuffer);
    free(state->gainBuffer);

    if (state->preFilterSetup) vDSP_biquad_DestroySetup(state->preFilterSetup);
    if (state->rlbFilterSetup) vDSP_biquad_DestroySetup(state->rlbFilterSetup);
    if (state->hpSetup) vDSP_biquad_DestroySetup(state->hpSetup);

    // Note: stats is freed by analysis module if enabled

    free(state);
}

void VBN_Reset(VBNState* state) {
    if (!state) return;

    // Reset LUFS state
    memset(state->sampleBuffer, 0, state->bufferSize * sizeof(float));
    state->writeIndex = 0;
    state->samplesAccumulated = 0;
    memset(state->preFilterDelays, 0, sizeof(state->preFilterDelays));
    memset(state->rlbFilterDelays, 0, sizeof(state->rlbFilterDelays));
    memset(state->blockLoudnesses, 0, sizeof(state->blockLoudnesses));
    state->blockCount = 0;
    state->currentLUFS = -24.0f;
    state->currentGain = 1.0f;
    state->targetGain = 1.0f;
    state->lastAppliedGain = 1.0f;
    state->hasInitialMeasurement = false;

    // Reset high-pass filter
    memset(state->hpDelays, 0, sizeof(state->hpDelays));

    // Reset compressor
    memset(state->compEnvelopes, 0, sizeof(state->compEnvelopes));

    // Reset limiter
    state->limiterGain = 1.0f;
    dequeClear(state);
    memset(state->truePeakHistory, 0, sizeof(state->truePeakHistory));

    // Reset temporary before-processing measurements
    state->lastBeforeRMS = -100.0f;
    state->lastBeforePeak = -100.0f;
    state->lastBeforeTruePeak = -100.0f;
}

// ============================================================================
// Main Processing
// ============================================================================

void VBN_Process(VBNState* state,
                 float* const* channels,
                 int frameCount,
                 int channelCount) {
    if (!state || !channels || frameCount <= 0 || channelCount <= 0) return;

    applyStagedConfigIfNeeded(state);

    // Step 1: LUFS measurement updates currentGain toward the target
    processLUFS(state, channels, frameCount, channelCount);

    // Step 2: Apply gain with a per-sample ramp so gain changes never click
    float rampStart = state->lastAppliedGain;
    float rampEnd = state->currentGain;
    if (fabsf(rampEnd - rampStart) > 1e-6f) {
        if (state->gainRampSize < frameCount) {
            free(state->gainRamp);
            state->gainRamp = (float*)malloc(frameCount * sizeof(float));
            state->gainRampSize = state->gainRamp ? frameCount : 0;
        }
        if (state->gainRamp) {
            vDSP_vgen(&rampStart, &rampEnd, state->gainRamp, 1, frameCount);
            for (int ch = 0; ch < channelCount; ch++) {
                vDSP_vmul(channels[ch], 1, state->gainRamp, 1, channels[ch], 1, frameCount);
            }
        }
    } else if (rampEnd != 1.0f) {
        for (int ch = 0; ch < channelCount; ch++) {
            vDSP_vsmul(channels[ch], 1, &rampEnd, channels[ch], 1, frameCount);
        }
    }
    state->lastAppliedGain = rampEnd;

    // Steps 3+4: per-channel filtering and compression
    for (int ch = 0; ch < channelCount; ch++) {
        float* samples = channels[ch];

        if (state->config.hpEnabled) {
            applyHighPass(state, samples, frameCount, ch);
        }

        if (state->config.compEnabled) {
            applyCompression(state, samples, frameCount, ch);
        }
    }

    // Step 5: Peak limiter (processes all channels together)
    applyLimiter(state, channels, frameCount, channelCount);
}

// ============================================================================
// State Queries
// ============================================================================

float VBN_GetCurrentGainDB(const VBNState* state) {
    if (!state) return 0.0f;
    return 20.0f * log10f(fmaxf(state->currentGain, 0.001f));
}

float VBN_GetMeasuredLUFS(const VBNState* state) {
    if (!state) return -70.0f;
    return state->currentLUFS;
}

float VBN_GetLimiterReductionDB(const VBNState* state) {
    if (!state) return 0.0f;
    return 20.0f * log10f(fmaxf(state->limiterGain, 0.001f));
}

float VBN_GetTargetLUFS(const VBNState* state) {
    if (!state) return VBN_TARGET_LUFS;
    return state->config.targetLUFS;
}

// ============================================================================
// Filter Coefficient Calculation
// ============================================================================

// Calculate K-weighting filter coefficients (ITU BS.1770-4)
// Formulas from Brecht De Man's implementation matching ITU-R BS.1770-4
void VBN_ComputeKWeightingCoeffs(double sampleRate, double preOut[5], double rlbOut[5]) {
    double sr = sampleRate;

    // Stage 1: High-shelf pre-filter (head model)
    // Parameters derived from ITU-R BS.1770-4 for 48kHz, scaled for other rates
    double f0_pre = 1681.9744509555319;
    double G_pre = 3.99984385397;  // dB
    double Q_pre = 0.7071752369554193;

    double K = tan(M_PI * f0_pre / sr);
    double K2 = K * K;
    double Vh = pow(10.0, G_pre / 20.0);
    double Vb = pow(Vh, 0.499666774155);  // Critical ITU-specific constant
    double a0_pre = 1.0 + K / Q_pre + K2;

    preOut[0] = (Vh + Vb * K / Q_pre + K2) / a0_pre;
    preOut[1] = 2.0 * (K2 - Vh) / a0_pre;
    preOut[2] = (Vh - Vb * K / Q_pre + K2) / a0_pre;
    preOut[3] = 2.0 * (K2 - 1.0) / a0_pre;
    preOut[4] = (1.0 - K / Q_pre + K2) / a0_pre;

    // Stage 2: High-pass RLB filter
    double f0_rlb = 38.13547087613982;
    double Q_rlb = 0.5003270373253953;

    double Krlb = tan(M_PI * f0_rlb / sr);
    double Krlb2 = Krlb * Krlb;
    double a0_rlb = 1.0 + Krlb / Q_rlb + Krlb2;

    rlbOut[0] = 1.0;
    rlbOut[1] = -2.0;
    rlbOut[2] = 1.0;
    rlbOut[3] = 2.0 * (Krlb2 - 1.0) / a0_rlb;
    rlbOut[4] = (1.0 - Krlb / Q_rlb + Krlb2) / a0_rlb;
}

static void createLUFSFilterSetups(VBNState* state) {
    double preCoeffs[5];
    double rlbCoeffs[5];
    VBN_ComputeKWeightingCoeffs(state->sampleRate, preCoeffs, rlbCoeffs);

    state->preFilterSetup = vDSP_biquad_CreateSetup(preCoeffs, 1);
    state->rlbFilterSetup = vDSP_biquad_CreateSetup(rlbCoeffs, 1);
}

// ============================================================================
// LUFS Measurement
// ============================================================================

static void processLUFS(VBNState* restrict state, float* const* restrict channels, int frameCount, int channelCount) {
    // Ensure scratch buffers are large enough
    if (state->tempBufferSize < frameCount) {
        free(state->tempBuffer);
        state->tempBuffer = (float*)malloc(frameCount * sizeof(float));
        state->tempBufferSize = state->tempBuffer ? frameCount : 0;
    }
    if (state->energyBufferSize < frameCount) {
        free(state->energyBuffer);
        state->energyBuffer = (float*)malloc(frameCount * sizeof(float));
        state->energyBufferSize = state->energyBuffer ? frameCount : 0;
    }
    if (!state->tempBuffer || !state->energyBuffer) return;

    // BS.1770-4 multichannel: K-weight each channel independently, then sum
    // per-sample squared energy across channels (podcasts are mono/stereo; the
    // state carries filter delays for up to 2 channels).
    int measureChannels = channelCount < 2 ? channelCount : 2;
    vDSP_vclr(state->energyBuffer, 1, frameCount);

    for (int ch = 0; ch < measureChannels; ch++) {
        memcpy(state->tempBuffer, channels[ch], frameCount * sizeof(float));

        // Apply K-weighting filters (ITU BS.1770-4)
        vDSP_biquad(state->preFilterSetup, state->preFilterDelays[ch], state->tempBuffer, 1, state->tempBuffer, 1, frameCount);
        vDSP_biquad(state->rlbFilterSetup, state->rlbFilterDelays[ch], state->tempBuffer, 1, state->tempBuffer, 1, frameCount);

        vDSP_vsq(state->tempBuffer, 1, state->tempBuffer, 1, frameCount);
        vDSP_vadd(state->energyBuffer, 1, state->tempBuffer, 1, state->energyBuffer, 1, frameCount);
    }

    // Copy summed energy into the circular buffer
    int remaining = frameCount;
    int srcOffset = 0;

    while (remaining > 0) {
        int spaceInBuffer = state->bufferSize - state->writeIndex;
        int copyCount = (remaining < spaceInBuffer) ? remaining : spaceInBuffer;

        memcpy(state->sampleBuffer + state->writeIndex,
               state->energyBuffer + srcOffset,
               copyCount * sizeof(float));

        state->writeIndex = (state->writeIndex + copyCount) & state->bufferMask;
        state->samplesAccumulated += copyCount;
        srcOffset += copyCount;
        remaining -= copyCount;

        // Measure when we cross hop boundary
        while (state->samplesAccumulated >= state->hopSize) {
            state->samplesAccumulated -= state->hopSize;
            measureBlock(state);
        }
    }

    // Gain smoothing. Per-sample ramping in VBN_Process keeps any convergence
    // speed click-free, so smoothing can be fast or adaptive.
    float tau = state->config.gainSmoothingTauSeconds;
    if (state->config.adaptiveGainSmoothing) {
        float errorDB = fabsf(20.0f * log10f(fmaxf(state->targetGain, 1e-6f) / fmaxf(state->currentGain, 1e-6f)));
        if (errorDB > 10.0f) {
            tau = VBN_GAIN_SMOOTH_TAU_FAST;
        } else if (errorDB > 5.0f) {
            tau = VBN_GAIN_SMOOTH_TAU_MEDIUM;
        } else if (errorDB > 2.0f) {
            tau = VBN_GAIN_SMOOTH_TAU_SLOW;
        } else {
            tau = fminf(tau, VBN_GAIN_SMOOTH_TAU_STABLE);
        }
    }
    if (tau < 0.01f) tau = 0.01f;
    float alpha = expf(-(float)frameCount / (tau * (float)state->sampleRate));
    state->currentGain = alpha * state->currentGain + (1.0f - alpha) * state->targetGain;
}

static void measureBlock(VBNState* state) {
    // sampleBuffer holds per-sample K-weighted squared energy (all channels
    // summed), so the block mean is a straight average.
    float energySum = 0;
    int startIndex = (state->writeIndex - state->blockSize + state->bufferSize) & state->bufferMask;

    // Check if block is contiguous
    if (startIndex + state->blockSize <= state->bufferSize) {
        vDSP_sve(state->sampleBuffer + startIndex, 1, &energySum, state->blockSize);
    } else {
        // Block wraps around
        int firstPart = state->bufferSize - startIndex;
        int secondPart = state->blockSize - firstPart;

        float sum1 = 0, sum2 = 0;
        vDSP_sve(state->sampleBuffer + startIndex, 1, &sum1, firstPart);
        vDSP_sve(state->sampleBuffer, 1, &sum2, secondPart);
        energySum = sum1 + sum2;
    }

    float meanSquare = energySum / (float)state->blockSize;
    if (meanSquare <= 0) return;

    float blockLoudness = -0.691f + 10.0f * log10f(meanSquare);

    // Absolute gate: only include blocks above -70 LUFS
    if (blockLoudness > VBN_ABSOLUTE_THRESHOLD) {
        // Shift array if full
        if (state->blockCount >= VBN_MAX_BLOCKS) {
            memmove(state->blockLoudnesses, state->blockLoudnesses + 1, (VBN_MAX_BLOCKS - 1) * sizeof(float));
            state->blockCount = VBN_MAX_BLOCKS - 1;
        }
        state->blockLoudnesses[state->blockCount++] = blockLoudness;

        // ITU BS.1770-4 two-pass gating:
        // Pass 1: Calculate ungated loudness (blocks above absolute threshold)
        // Pass 2: Apply relative gate (-10 LU below ungated average)
        if (state->blockCount > 0) {
            // Pass 1: Ungated average (already filtered by absolute gate)
            float sumMeanSquare = 0;
            for (int i = 0; i < state->blockCount; i++) {
                sumMeanSquare += powf(10.0f, (state->blockLoudnesses[i] + 0.691f) / 10.0f);
            }
            float ungatedLUFS = -0.691f + 10.0f * log10f(sumMeanSquare / (float)state->blockCount);

            // Pass 2: Relative gate threshold
            float relativeThreshold = ungatedLUFS + VBN_RELATIVE_THRESHOLD;

            // Recalculate with relative gate applied
            float gatedSum = 0;
            int gatedCount = 0;
            for (int i = 0; i < state->blockCount; i++) {
                if (state->blockLoudnesses[i] > relativeThreshold) {
                    gatedSum += powf(10.0f, (state->blockLoudnesses[i] + 0.691f) / 10.0f);
                    gatedCount++;
                }
            }

            // Use gated measurement if we have enough blocks, otherwise use ungated
            if (gatedCount > 0) {
                state->currentLUFS = -0.691f + 10.0f * log10f(gatedSum / (float)gatedCount);
            } else {
                state->currentLUFS = ungatedLUFS;
            }

            // Calculate target gain
            float requiredGainDB = state->config.targetLUFS - state->currentLUFS;

            // Clamp gain
            if (requiredGainDB > state->config.maxGainDB) requiredGainDB = state->config.maxGainDB;
            if (requiredGainDB < state->config.minGainDB) requiredGainDB = state->config.minGainDB;

            state->targetGain = powf(10.0f, requiredGainDB / 20.0f);
            state->hasInitialMeasurement = true;
        }
    }
}

// ============================================================================
// High-Pass Filter
// ============================================================================

static void applyHighPass(VBNState* restrict state, float* restrict samples, int frameCount, int channel) {
    if (channel >= 2 || !state->hpSetup) return;
    vDSP_biquad(state->hpSetup, state->hpDelays[channel], samples, 1, samples, 1, frameCount);
}

// ============================================================================
// Compression
// ============================================================================

static void applyCompression(VBNState* restrict state, float* restrict samples, int frameCount, int channel) {
    if (channel >= 2) return;

    float thresh = state->compThreshold;
    float slope = state->compSlope;
    float kneeWidthDB = state->config.compKneeWidthDB;
    float kneeLow = state->compKneeLowLinear;
    float* envelope = &state->compEnvelopes[channel];

    // The level below which no gain reduction can occur (knee start, or the
    // threshold itself for a hard knee)
    float silentLevel = (kneeWidthDB > 0) ? kneeLow : thresh;

    // Vectorized early exit check
    float maxLevel = 0;
    vDSP_maxmgv(samples, 1, &maxLevel, frameCount);

    // If signal and envelope both well below any gain reduction, skip processing
    if (maxLevel < silentLevel * 0.5f && *envelope < silentLevel * 0.5f) {
        float coef = state->compReleaseCoef;
        float effectiveCoef = powf(coef, (float)frameCount);
        *envelope = effectiveCoef * (*envelope) + (1.0f - effectiveCoef) * maxLevel;
        return;
    }

    // Pre-compute absolute values using vDSP when a safe buffer is available.
    float stackBuffer[2048];
    float* absBuffer = NULL;
    if (state->peakBuffer && state->maxLimiterBufferSize >= frameCount) {
        absBuffer = state->peakBuffer;
    } else if (frameCount <= 2048) {
        absBuffer = stackBuffer;
    }
    if (absBuffer) {
        vDSP_vabs(samples, 1, absBuffer, 1, frameCount);
    }

    float attCoef = state->compAttackCoef;
    float relCoef = state->compReleaseCoef;
    float env = *envelope;
    float thresholdDB = state->config.compThresholdDB;
    // (1/R - 1): dB of gain reduction per dB over threshold, negative
    float slopeDB = 1.0f / fmaxf(state->config.compRatio, 1.0f) - 1.0f;

    // Envelope follower with gain application (sequential due to feedback)
    for (int i = 0; i < frameCount; i++) {
        float inputLevel = absBuffer ? absBuffer[i] : fabsf(samples[i]);

        float coef = (inputLevel > env) ? attCoef : relCoef;
        env = coef * env + (1.0f - coef) * inputLevel;

        if (kneeWidthDB <= 0.0f) {
            // Hard knee (historical behavior, kept bit-exact)
            if (env > thresh) {
                float ratio = thresh / env;
                float gain = 1.0f - slope * (1.0f - ratio);
                if (gain < 0.1f) gain = 0.1f;
                samples[i] *= gain;
            }
        } else if (env > kneeLow) {
            // Soft knee: quadratic interpolation across the knee region (dB domain)
            float envDB = 20.0f * log10f(env);
            float over = envDB - thresholdDB;
            float reductionDB;
            if (2.0f * over <= -kneeWidthDB) {
                reductionDB = 0.0f;
            } else if (2.0f * over < kneeWidthDB) {
                float t = over + kneeWidthDB * 0.5f;
                reductionDB = slopeDB * t * t / (2.0f * kneeWidthDB);
            } else {
                reductionDB = slopeDB * over;
            }

            if (reductionDB < 0.0f) {
                float gain = powf(10.0f, reductionDB / 20.0f);
                if (gain < 0.1f) gain = 0.1f;
                samples[i] *= gain;
            }
        }
    }

    *envelope = env;
}

// ============================================================================
// Peak Limiter
// ============================================================================

// ITU-R BS.1770-4 Annex 2 interpolation filter for 4x oversampled true-peak
// estimation: a 48-tap windowed-sinc split into 4 polyphase branches of 12 taps.
static const float kTruePeakPhaseCoeffs[VBN_TRUE_PEAK_PHASES][VBN_TRUE_PEAK_TAPS] = {
    { 0.0017089843750f, 0.0109863281250f, -0.0196533203125f, 0.0332031250000f,
      -0.0594482421875f, 0.1373291015625f, 0.9721679687500f, -0.1022949218750f,
      0.0476074218750f, -0.0266113281250f, 0.0148925781250f, -0.0083007812500f },
    { -0.0291748046875f, 0.0292968750000f, -0.0517578125000f, 0.0891113281250f,
      -0.1665039062500f, 0.4650878906250f, 0.7797851562500f, -0.2003173828125f,
      0.1015625000000f, -0.0582275390625f, 0.0330810546875f, -0.0189208984375f },
    { -0.0189208984375f, 0.0330810546875f, -0.0582275390625f, 0.1015625000000f,
      -0.2003173828125f, 0.7797851562500f, 0.4650878906250f, -0.1665039062500f,
      0.0891113281250f, -0.0517578125000f, 0.0292968750000f, -0.0291748046875f },
    { -0.0083007812500f, 0.0148925781250f, -0.0266113281250f, 0.0476074218750f,
      -0.1022949218750f, 0.9721679687500f, 0.1373291015625f, -0.0594482421875f,
      0.0332031250000f, -0.0196533203125f, 0.0109863281250f, 0.0017089843750f }
};

// Per-sample true-peak magnitude estimate: the max of the sample magnitude and
// the four interpolated inter-sample magnitudes. Costs ~48 MAC/sample/channel.
static void computeTruePeakMagnitudes(VBNState* restrict state, int channel, const float* restrict samples, float* restrict outPeaks, int frameCount) {
    float* history = state->truePeakHistory[channel];

    for (int i = 0; i < frameCount; i++) {
        // Shift history: history[0] is the newest sample
        memmove(history + 1, history, (VBN_TRUE_PEAK_TAPS - 1) * sizeof(float));
        history[0] = samples[i];

        float peak = fabsf(samples[i]);
        for (int phase = 0; phase < VBN_TRUE_PEAK_PHASES; phase++) {
            const float* coeffs = kTruePeakPhaseCoeffs[phase];
            float acc = 0.0f;
            for (int tap = 0; tap < VBN_TRUE_PEAK_TAPS; tap++) {
                acc += coeffs[tap] * history[tap];
            }
            float mag = fabsf(acc);
            if (mag > peak) peak = mag;
        }

        outPeaks[i] = peak;
    }
}

static void applyLimiter(VBNState* restrict state, float* const* restrict channels, int frameCount, int channelCount) {
    bool truePeak = state->config.truePeakEnabled;
    float ceiling = state->limiterCeilingLinear;

    // Ensure buffers are large enough
    if (state->maxLimiterBufferSize < frameCount) {
        free(state->peakBuffer);
        free(state->gainBuffer);
        state->peakBuffer = (float*)malloc(frameCount * sizeof(float));
        state->gainBuffer = (float*)malloc(frameCount * sizeof(float));
        state->maxLimiterBufferSize = (state->peakBuffer && state->gainBuffer) ? frameCount : 0;
    }
    if (!state->peakBuffer || !state->gainBuffer) return;

    if (!truePeak) {
        // Early exit: check if max signal is well below ceiling. (Skipped in
        // true-peak mode so the interpolation history stays continuous.)
        float maxSignal = 0;
        for (int ch = 0; ch < channelCount; ch++) {
            float chMax = 0;
            vDSP_maxmgv(channels[ch], 1, &chMax, frameCount);
            if (chMax > maxSignal) maxSignal = chMax;
        }

        if (maxSignal < ceiling * 0.7f && state->limiterGain > 0.99f) {
            return;  // No limiting needed
        }

        // Build peak buffer using sample-peak detection
        vDSP_vabs(channels[0], 1, state->peakBuffer, 1, frameCount);
        for (int ch = 1; ch < channelCount && ch < 2; ch++) {
            vDSP_vabs(channels[ch], 1, state->gainBuffer, 1, frameCount);
            vDSP_vmax(state->peakBuffer, 1, state->gainBuffer, 1, state->peakBuffer, 1, frameCount);
        }
    } else {
        // Build peak buffer from 4x oversampled true-peak magnitudes
        computeTruePeakMagnitudes(state, 0, channels[0], state->peakBuffer, frameCount);
        for (int ch = 1; ch < channelCount && ch < 2; ch++) {
            computeTruePeakMagnitudes(state, ch, channels[ch], state->gainBuffer, frameCount);
            vDSP_vmax(state->peakBuffer, 1, state->gainBuffer, 1, state->peakBuffer, 1, frameCount);
        }
    }

    // Initialize gain buffer to 1.0
    float one = 1.0f;
    vDSP_vfill(&one, state->gainBuffer, 1, frameCount);

    // O(n) sliding maximum using ring buffer deque
    dequeClear(state);

    for (int i = 0; i < frameCount; i++) {
        int addIdx = i + state->lookaheadSamples;
        if (addIdx < frameCount) {
            float newPeak = state->peakBuffer[addIdx];
            while (!dequeIsEmpty(state) && dequeBackVal(state) <= newPeak) {
                dequePopBack(state);
            }
            dequePushBack(state, addIdx, newPeak);
        }

        while (!dequeIsEmpty(state) && dequeFrontIdx(state) < i) {
            dequePopFront(state);
        }

        float currentPeak = state->peakBuffer[i];
        float windowMax = dequeIsEmpty(state) ? currentPeak : fmaxf(dequeFrontVal(state), currentPeak);

        if (windowMax > ceiling) {
            state->gainBuffer[i] = ceiling / windowMax;
        }
    }

    // Apply gain with instant attack, smooth release
    // Instant attack is required to catch peaks - lookahead provides smoothing
    float gainState = state->limiterGain;
    float releaseCoef = state->limiterReleaseCoef;

    for (int i = 0; i < frameCount; i++) {
        float required = state->gainBuffer[i];
        if (required < gainState) {
            gainState = required;  // Instant attack (lookahead makes this smooth)
        } else {
            gainState = gainState + releaseCoef * (1.0f - gainState);  // Smooth release
        }
        state->gainBuffer[i] = gainState;
    }

    // Apply gain to all channels
    for (int ch = 0; ch < channelCount; ch++) {
        vDSP_vmul(channels[ch], 1, state->gainBuffer, 1, channels[ch], 1, frameCount);
    }

    state->limiterGain = gainState;
}
