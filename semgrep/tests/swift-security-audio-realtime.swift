import AVFoundation
import Foundation

let unsafeAudioTapProcess: MTAudioProcessingTapProcessCallback = { _, _, _, _, _, _ in
    let lock = NSLock()

    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    lock.lock()
    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    objc_sync_enter(lock)
    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    FileLog.shared.addMessage("rendering")
    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    FileLog.shared.console("rendering")
    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    _ = VBN_Create(44_100)
    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    _ = VBN_CreateWithConfig(44_100, nil)
    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    VBN_Destroy(nil)
    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    _ = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)
    // ruleid: pocketcasts.no-blocking-work-in-audio-tap-process
    _ = AVAudioConverter(from: format, to: format)
}

let safeAudioTapProcess: MTAudioProcessingTapProcessCallback = { _, _, _, _, _, _ in
    // ok: pocketcasts.no-blocking-work-in-audio-tap-process
    tapState.withLockIfAvailable { $0.enabled }
    // ok: pocketcasts.no-blocking-work-in-audio-tap-process
    VBN_SetConfig(vbnState, nil)
}

let safeAudioTapPrepare: MTAudioProcessingTapPrepareCallback = { _, _, _ in
    // ok: pocketcasts.no-blocking-work-in-audio-tap-process
    _ = VBN_CreateWithConfig(44_100, nil)
    // ok: pocketcasts.no-blocking-work-in-audio-tap-process
    FileLog.shared.addMessage("prepared")
}
