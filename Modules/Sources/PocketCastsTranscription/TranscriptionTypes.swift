import Foundation

/// A single recognized word with audio timings, in seconds from the start of the audio file.
public struct TranscriptWord: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A contiguous run of recognized speech from an ASR engine. `words` is populated
/// when the engine provides word-level timings; segment-level engines leave it nil.
public struct ASRSegment: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let words: [TranscriptWord]?

    public init(text: String, start: TimeInterval, end: TimeInterval, words: [TranscriptWord]? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
    }
}

/// A "who spoke when" interval from a diarizer. `speakerId` is the diarizer's raw
/// label (e.g. "SPEAKER_00"); `SpeakerAligner` normalizes labels to "Speaker 1…N".
public struct SpeakerTurn: Sendable, Equatable {
    public let speakerId: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speakerId: String, start: TimeInterval, end: TimeInterval) {
        self.speakerId = speakerId
        self.start = start
        self.end = end
    }
}

/// A display cue: speaker-attributed text over a time range. `speaker` is nil for
/// monologues (and unattributable gaps), in which case the VTT serializer omits the
/// `<v>` voice tag.
public struct DiarizedCue: Sendable, Equatable {
    public let speaker: String?
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speaker: String?, text: String, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }
}

/// The finished product of the transcription pipeline, ready for VTT serialization.
public struct DiarizedTranscript: Sendable, Equatable {
    public let cues: [DiarizedCue]
    public let language: String?
    public let speakerCount: Int
    public let engineDescription: String

    public init(cues: [DiarizedCue], language: String?, speakerCount: Int, engineDescription: String) {
        self.cues = cues
        self.language = language
        self.speakerCount = speakerCount
        self.engineDescription = engineDescription
    }
}

/// Which of the three engine stacks produced (or should produce) a transcription.
/// Raw values are persisted in the `EpisodeTranscription.engineMode` DB column —
/// never renumber.
public enum TranscriptionEngineMode: Int32, Sendable, CaseIterable {
    case appleBuiltIn = 0
    case localModel = 1
    case remoteProvider = 2
}

/// Failures surfaced by engines, diarizers and remote providers. Cases map onto
/// user-facing recovery guidance in the app layer.
public enum TranscriptionError: Error, Sendable, Equatable {
    /// Remote provider rejected the key (HTTP 401/403).
    case invalidAPIKey
    /// Remote provider refused for billing/rate reasons (HTTP 402/429).
    case quotaExceeded
    /// Upload exceeds the provider's file size cap.
    case audioTooLarge(limitMB: Int)
    /// The audio format can't be handled by the selected engine/provider.
    case unsupportedAudio
    /// Remote job reached a terminal failure state; payload is the provider's message.
    case remoteJobFailed(String)
    case networkUnavailable
    /// Episode audio is not downloaded and the engine requires a local file.
    case notDownloaded
    /// Local audio file is missing or unreadable.
    case audioUnreadable
    /// On-device model/asset download failed.
    case modelDownloadFailed
    /// Engine failed for a reason with no more specific case.
    case engineFailure
    /// Device is too hot; job stays queued for a cooler/charging pass.
    case thermalThrottled
    case cancelled
}

/// How a remote provider receives the episode audio.
public enum RemoteAudioSource: Sendable {
    /// Provider fetches the episode's public download URL itself (no upload).
    case publicURL(URL)
    /// Provider receives an upload of the local file at this URL.
    case fileUpload(URL, mimeType: String)
}

/// Opaque, persistable reference to an asynchronous remote transcription job.
/// `providerData` carries whatever extra state the provider needs to poll
/// (upload URIs, region hints, …) without the module knowing its shape.
public struct RemoteJobHandle: Sendable, Equatable, Codable {
    public let providerId: String
    public let jobId: String
    public let providerData: [String: String]

    public init(providerId: String, jobId: String, providerData: [String: String] = [:]) {
        self.providerId = providerId
        self.jobId = jobId
        self.providerData = providerData
    }
}

/// Result of submitting audio to a remote provider. Synchronous providers
/// (Deepgram, ElevenLabs) return `.completed` directly — no adapter-side state.
public enum SubmitOutcome: Sendable {
    case job(RemoteJobHandle)
    case completed(DiarizedTranscript)
}

/// Poll result for an asynchronous remote job. `.processing` carries the
/// provider-reported fractional progress when available.
public enum RemoteJobStatus: Sendable {
    case processing(Double?)
    case completed(DiarizedTranscript)
    case failed(TranscriptionError)
}
