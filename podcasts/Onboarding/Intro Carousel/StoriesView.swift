import Combine
import SwiftUI

@MainActor
protocol StoriesDataSource {
    var numberOfStories: Int { get }

    func story(for index: Int) -> any StoryView
    func storyView(for index: Int) -> AnyView
    func shareableStory(for index: Int) -> (any ShareableStory)?
    func isInteractiveView(for index: Int) -> Bool
    func isReady() async -> Bool
    func refresh() async -> Bool
    func paywallView() -> AnyView
    func overlaidShareView() -> AnyView?
    func footerShareView() -> AnyView?
    func indicatorColor(for storyIndex: Int) -> Color
    func indicatorStyle(for storyIndex: Int) -> StoryIndicatorStyle
    var primaryBackgroundColor: Color { get }
    func sharingSnapshotModifier(_ view: AnyView) -> AnyView
}

extension StoriesDataSource {
    func storyView(for index: Int) -> AnyView {
        AnyView(story(for: index))
    }

    func isInteractiveView(for index: Int) -> Bool {
        false
    }
}

typealias StoryView = Story & View

@MainActor
protocol Story {
    var duration: TimeInterval { get }
    var identifier: String { get }
    var plusOnly: Bool { get }
    var shouldPause: Bool { get }

    func onAppear()
    func onPause()
    func onResume()
}

extension Story {
    var duration: TimeInterval { 7 }
    var identifier: String { "unknown" }
    var plusOnly: Bool { false }
    var shouldPause: Bool { false }

    func onAppear() {}
    func onPause() {}
    func onResume() {}
}

typealias ShareableStory = StoryView & StorySharing

protocol StorySharing {
    func willShare()
    func sharingAssets() -> [Any]
    func hideShareButton() -> Bool
}

extension StorySharing {
    func willShare() {}
    func sharingAssets() -> [Any] { [] }
    func hideShareButton() -> Bool { false }
}

struct StoriesView: View {
    @ObservedObject private var progressModel = StoriesProgressModel.shared

    private let dataSource: StoriesDataSource
    private let configuration: StoriesConfiguration

    @State private var isReady = false
    @State private var isPaused = false
    @State private var isVisible = false
    @State private var currentStoryIndex = 0
    @State private var storyStartDate = Date()
    @State private var timerSubscription: Cancellable?
    @State private var timer = Timer.publish(every: 0.02, on: .main, in: .common)

    init(dataSource: StoriesDataSource, configuration: StoriesConfiguration = StoriesConfiguration()) {
        self.dataSource = dataSource
        self.configuration = configuration
    }

    var body: some View {
        ZStack {
            if isReady, dataSource.numberOfStories > 0 {
                dataSource.storyView(for: currentStoryIndex)
                    .onAppear {
                        startStory(at: currentStoryIndex)
                    }

                storySwitcher
                indicators
            } else {
                dataSource.primaryBackgroundColor
            }
        }
        .background(dataSource.primaryBackgroundColor)
        .task {
            isReady = await dataSource.refresh()
            if isReady, dataSource.numberOfStories > 0 {
                startStory(at: 0)
            }
        }
        .onReceive(timer) { _ in
            updateProgress()
        }
        .onAppear {
            isVisible = true
            updateTimerSubscription()
        }
        .onDisappear {
            isVisible = false
            stopTimer()
        }
        .onChange(of: isReady) { _, _ in
            updateTimerSubscription()
        }
        .onChange(of: isPaused) { _, _ in
            updateTimerSubscription()
        }
    }

    private var indicators: some View {
        VStack {
            HStack(spacing: configuration.indicatorSpacing) {
                ForEach(Array(0 ..< dataSource.numberOfStories), id: \.self) { index in
                    StoryIndicator(
                        index: index,
                        style: dataSource.indicatorStyle(for: index),
                        progressModel: progressModel
                    )
                }
            }
            .frame(height: configuration.indicatorHeight)
            .padding(.horizontal, 15)
            .padding(.top, 4)

            Spacer()
        }
    }

    private var storySwitcher: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    showPreviousStory()
                }

            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    showNextStory()
                }
        }
    }

    private func startStory(at index: Int) {
        guard dataSource.numberOfStories > 0 else {
            return
        }

        let boundedIndex = min(max(index, 0), dataSource.numberOfStories - 1)
        currentStoryIndex = boundedIndex
        storyStartDate = Date()
        progressModel.progress = Double(boundedIndex)

        let story = dataSource.story(for: boundedIndex)
        story.onAppear()
        isPaused = story.shouldPause
    }

    private func updateProgress() {
        guard isReady, !isPaused, dataSource.numberOfStories > 0 else {
            return
        }

        let story = dataSource.story(for: currentStoryIndex)
        let duration = max(story.duration, 0.1)
        let elapsed = Date().timeIntervalSince(storyStartDate)
        let progressInStory = min(elapsed / duration, 1)
        progressModel.progress = Double(currentStoryIndex) + progressInStory

        if progressInStory >= 1 {
            showNextStory()
        }
    }

    private func showNextStory() {
        if currentStoryIndex + 1 < dataSource.numberOfStories {
            startStory(at: currentStoryIndex + 1)
        } else if configuration.startOverFromBeginningAfterFinished {
            startStory(at: 0)
        } else {
            isPaused = true
            progressModel.progress = Double(dataSource.numberOfStories)
        }
    }

    private func showPreviousStory() {
        startStory(at: max(currentStoryIndex - 1, 0))
    }

    private func updateTimerSubscription() {
        guard isVisible, isReady, !isPaused, dataSource.numberOfStories > 0 else {
            stopTimer()
            return
        }

        guard timerSubscription == nil else { return }
        timerSubscription = timer.connect()
    }

    private func stopTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
    }
}
