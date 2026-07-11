/**
 * VoiceBoostN Loudness Meter Implementation
 *
 * Incremental ITU-R BS.1770-4 integrated loudness: per-channel K-weighting,
 * 400 ms blocks with 100 ms hop, and two-pass gating (absolute -70 LUFS,
 * relative -10 LU) applied over the full set of block energies at read time.
 *
 * Memory: one double per 100 ms block — a 3 h file is ~108k blocks ≈ 864 KB.
 */

#include "VoiceBoostNMeter.h"
#include "../VoiceBoostN_Internal.h"
#include <Accelerate/Accelerate.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define METER_MAX_CHANNELS 2
#define METER_ABSOLUTE_GATE -70.0
#define METER_RELATIVE_GATE -10.0

struct VBNLoudnessMeter {
    double sampleRate;
    int channels;

    vDSP_biquad_Setup preSetup;
    vDSP_biquad_Setup rlbSetup;
    float preDelays[METER_MAX_CHANNELS][4];
    float rlbDelays[METER_MAX_CHANNELS][4];

    // Circular buffer of per-sample K-weighted energy summed across channels
    float* energyRing;
    int ringSize;
    int ringMask;
    int writeIndex;
    long long totalSamples;
    int samplesSinceHop;
    int blockSize;
    int hopSize;

    // Scratch
    float* scratch;
    float* energyScratch;
    int scratchSize;

    // Per-block mean-square energies, grown as the file is fed
    double* blockEnergies;
    int blockCount;
    int blockCapacity;
};

VBNLoudnessMeter* VBN_MeterCreate(double sampleRate, int maxChannels) {
    if (sampleRate <= 0) return NULL;

    VBNLoudnessMeter* meter = (VBNLoudnessMeter*)calloc(1, sizeof(VBNLoudnessMeter));
    if (!meter) return NULL;

    meter->sampleRate = sampleRate;
    meter->channels = maxChannels < METER_MAX_CHANNELS ? maxChannels : METER_MAX_CHANNELS;
    if (meter->channels < 1) meter->channels = 1;

    meter->blockSize = (int)(sampleRate * VBN_BLOCK_DURATION);
    meter->hopSize = (int)(sampleRate * VBN_BLOCK_DURATION * (1.0 - VBN_BLOCK_OVERLAP));

    int minSize = meter->blockSize * 2;
    meter->ringSize = 1;
    while (meter->ringSize < minSize) meter->ringSize <<= 1;
    meter->ringMask = meter->ringSize - 1;
    meter->energyRing = (float*)calloc(meter->ringSize, sizeof(float));

    double preCoeffs[5];
    double rlbCoeffs[5];
    VBN_ComputeKWeightingCoeffs(sampleRate, preCoeffs, rlbCoeffs);
    meter->preSetup = vDSP_biquad_CreateSetup(preCoeffs, 1);
    meter->rlbSetup = vDSP_biquad_CreateSetup(rlbCoeffs, 1);

    meter->blockCapacity = 4096;
    meter->blockEnergies = (double*)malloc(meter->blockCapacity * sizeof(double));

    if (!meter->energyRing || !meter->preSetup || !meter->rlbSetup || !meter->blockEnergies) {
        VBN_MeterDestroy(meter);
        return NULL;
    }

    return meter;
}

void VBN_MeterDestroy(VBNLoudnessMeter* meter) {
    if (!meter) return;

    free(meter->energyRing);
    free(meter->scratch);
    free(meter->energyScratch);
    free(meter->blockEnergies);
    if (meter->preSetup) vDSP_biquad_DestroySetup(meter->preSetup);
    if (meter->rlbSetup) vDSP_biquad_DestroySetup(meter->rlbSetup);
    free(meter);
}

static void meterAppendBlock(VBNLoudnessMeter* meter, double meanSquare) {
    if (meter->blockCount >= meter->blockCapacity) {
        int newCapacity = meter->blockCapacity * 2;
        double* grown = (double*)realloc(meter->blockEnergies, newCapacity * sizeof(double));
        if (!grown) return; // drop the block rather than fail the scan
        meter->blockEnergies = grown;
        meter->blockCapacity = newCapacity;
    }
    meter->blockEnergies[meter->blockCount++] = meanSquare;
}

static void meterMeasureBlock(VBNLoudnessMeter* meter) {
    // Skip until a whole block has been accumulated
    if (meter->totalSamples < meter->blockSize) return;

    float energySum = 0;
    int startIndex = (meter->writeIndex - meter->blockSize + meter->ringSize) & meter->ringMask;

    if (startIndex + meter->blockSize <= meter->ringSize) {
        vDSP_sve(meter->energyRing + startIndex, 1, &energySum, meter->blockSize);
    } else {
        int firstPart = meter->ringSize - startIndex;
        int secondPart = meter->blockSize - firstPart;
        float sum1 = 0, sum2 = 0;
        vDSP_sve(meter->energyRing + startIndex, 1, &sum1, firstPart);
        vDSP_sve(meter->energyRing, 1, &sum2, secondPart);
        energySum = sum1 + sum2;
    }

    double meanSquare = (double)energySum / (double)meter->blockSize;
    if (meanSquare > 0) {
        meterAppendBlock(meter, meanSquare);
    }
}

void VBN_MeterProcess(VBNLoudnessMeter* meter, const float* const* channels, int frameCount, int channelCount) {
    if (!meter || !channels || frameCount <= 0 || channelCount <= 0) return;

    if (meter->scratchSize < frameCount) {
        free(meter->scratch);
        free(meter->energyScratch);
        meter->scratch = (float*)malloc(frameCount * sizeof(float));
        meter->energyScratch = (float*)malloc(frameCount * sizeof(float));
        meter->scratchSize = (meter->scratch && meter->energyScratch) ? frameCount : 0;
    }
    if (!meter->scratch || !meter->energyScratch) return;

    int measureChannels = channelCount < meter->channels ? channelCount : meter->channels;
    vDSP_vclr(meter->energyScratch, 1, frameCount);

    for (int ch = 0; ch < measureChannels; ch++) {
        memcpy(meter->scratch, channels[ch], frameCount * sizeof(float));
        vDSP_biquad(meter->preSetup, meter->preDelays[ch], meter->scratch, 1, meter->scratch, 1, frameCount);
        vDSP_biquad(meter->rlbSetup, meter->rlbDelays[ch], meter->scratch, 1, meter->scratch, 1, frameCount);
        vDSP_vsq(meter->scratch, 1, meter->scratch, 1, frameCount);
        vDSP_vadd(meter->energyScratch, 1, meter->scratch, 1, meter->energyScratch, 1, frameCount);
    }

    int remaining = frameCount;
    int srcOffset = 0;

    while (remaining > 0) {
        int space = meter->ringSize - meter->writeIndex;
        int copyCount = remaining < space ? remaining : space;

        memcpy(meter->energyRing + meter->writeIndex, meter->energyScratch + srcOffset, copyCount * sizeof(float));

        meter->writeIndex = (meter->writeIndex + copyCount) & meter->ringMask;
        meter->totalSamples += copyCount;
        meter->samplesSinceHop += copyCount;
        srcOffset += copyCount;
        remaining -= copyCount;

        while (meter->samplesSinceHop >= meter->hopSize) {
            meter->samplesSinceHop -= meter->hopSize;
            meterMeasureBlock(meter);
        }
    }
}

float VBN_MeterIntegratedLUFS(const VBNLoudnessMeter* meter) {
    if (!meter || meter->blockCount == 0) return NAN;

    // Pass 1: absolute gate at -70 LUFS
    double sum = 0;
    int count = 0;
    for (int i = 0; i < meter->blockCount; i++) {
        double loudness = -0.691 + 10.0 * log10(meter->blockEnergies[i]);
        if (loudness > METER_ABSOLUTE_GATE) {
            sum += meter->blockEnergies[i];
            count++;
        }
    }
    if (count == 0) return NAN;

    double ungatedLUFS = -0.691 + 10.0 * log10(sum / (double)count);

    // Pass 2: relative gate at -10 LU below the ungated loudness
    double relativeThreshold = ungatedLUFS + METER_RELATIVE_GATE;
    double gatedSum = 0;
    int gatedCount = 0;
    for (int i = 0; i < meter->blockCount; i++) {
        double loudness = -0.691 + 10.0 * log10(meter->blockEnergies[i]);
        if (loudness > METER_ABSOLUTE_GATE && loudness > relativeThreshold) {
            gatedSum += meter->blockEnergies[i];
            gatedCount++;
        }
    }
    if (gatedCount == 0) return (float)ungatedLUFS;

    return (float)(-0.691 + 10.0 * log10(gatedSum / (double)gatedCount));
}
