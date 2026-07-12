import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen + Dynamic Island presentation for the Now Playing Live Activity.
/// Deliberately scoped to what the system player does not show: chapter context
/// and queue-aware controls, driven by the same background-capable
/// `PlaybackControlIntent` the Control Center widgets use.
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            LockScreenNowPlayingView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityArtworkView(fileName: context.state.artworkFileName)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.episodeTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.chapterTitle ?? context.state.podcastName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ActivityProgressView(state: context.state)
                        HStack(spacing: 28) {
                            Button(intent: PlaybackControlIntent(.skipBack)) {
                                Image(systemName: "gobackward")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            Button(intent: PlaybackControlIntent(.playPause)) {
                                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                            }
                            .buttonStyle(.plain)
                            Button(intent: PlaybackControlIntent(.skipForward)) {
                                Image(systemName: "goforward")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: {
                ActivityArtworkView(fileName: context.state.artworkFileName)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
                    .foregroundStyle(.tint)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
                    .foregroundStyle(.tint)
            }
        }
    }
}

private struct LockScreenNowPlayingView: View {
    let state: NowPlayingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ActivityArtworkView(fileName: state.artworkFileName)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(state.episodeTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(state.chapterTitle ?? state.podcastName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ActivityProgressView(state: state)
            }

            Button(intent: PlaybackControlIntent(.playPause)) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }
}

/// Progress that ticks on its own while playing (timer interval) and freezes
/// at the captured position while paused — no per-second activity updates.
private struct ActivityProgressView: View {
    let state: NowPlayingActivityAttributes.ContentState

    var body: some View {
        if state.duration > 0 {
            if state.isPlaying {
                let start = state.capturedAt.addingTimeInterval(-state.position)
                let end = start.addingTimeInterval(state.duration)
                ProgressView(timerInterval: start ... end, countsDown: false)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            } else {
                ProgressView(value: min(max(state.position / state.duration, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
        }
    }
}

private struct ActivityArtworkView: View {
    let fileName: String?

    var body: some View {
        if let image = loadImage() {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func loadImage() -> UIImage? {
        guard let fileName,
              let directory = NowPlayingActivityArtwork.containerURL(groupId: SharedConstants.GroupUserDefaults.groupContainerId) else {
            return nil
        }
        return UIImage(contentsOfFile: directory.appendingPathComponent(fileName).path)
    }
}
