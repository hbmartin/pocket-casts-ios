/**
 * VoiceBoostN Loudness Meter
 *
 * Incremental ITU-R BS.1770-4 integrated loudness measurement for offline
 * scanning of downloaded episodes. Feed the whole file through
 * VBN_MeterProcess in chunks, then read VBN_MeterIntegratedLUFS once at EOF.
 *
 * Shares the K-weighting filter design with the realtime VoiceBoostN
 * processor (VBN_ComputeKWeightingCoeffs).
 */

#ifndef VOICEBOOSTNMETER_H
#define VOICEBOOSTNMETER_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VBNLoudnessMeter VBNLoudnessMeter;

/**
 * Create a meter.
 *
 * @param sampleRate Audio sample rate in Hz
 * @param maxChannels Number of channels that will be fed (capped at 2)
 * @return New meter, or NULL on allocation failure
 */
VBNLoudnessMeter* VBN_MeterCreate(double sampleRate, int maxChannels);

/**
 * Feed a chunk of audio. Chunks may be any length; channel data is not modified.
 */
void VBN_MeterProcess(VBNLoudnessMeter* meter, const float* const* channels, int frameCount, int channelCount);

/**
 * The gated integrated loudness (BS.1770-4 two-pass gating: -70 LUFS absolute,
 * -10 LU relative) over everything fed so far.
 *
 * @return Integrated LUFS, or NAN when nothing measurable was fed
 */
float VBN_MeterIntegratedLUFS(const VBNLoudnessMeter* meter);

void VBN_MeterDestroy(VBNLoudnessMeter* meter);

#ifdef __cplusplus
}
#endif

#endif // VOICEBOOSTNMETER_H
