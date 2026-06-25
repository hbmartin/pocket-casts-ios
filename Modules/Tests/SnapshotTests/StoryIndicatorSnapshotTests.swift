#if canImport(UIKit)
import SnapshotTesting
import SwiftUI
import XCTest

import EndOfYear

final class StoryIndicatorSnapshotTests: XCTestCase {
    private let layout = SwiftUISnapshotLayout.fixed(width: 240, height: 28)
    private let style = StoryIndicatorStyle(
        height: 6,
        borderRadius: 3,
        backgroundOpacity: 0.25,
        foregroundOpacity: 1,
        backgroundColor: .white,
        foregroundColor: Color(red: 0.26, green: 0.86, blue: 0.58)
    )

    @MainActor
    func testUpcomingStoryProgress() {
        assertStoryProgress(0.35)
    }

    @MainActor
    func testCurrentStoryProgress() {
        assertStoryProgress(1.35)
    }

    @MainActor
    func testCompletedStoryProgress() {
        assertStoryProgress(2.1)
    }

    @MainActor
    private func assertStoryProgress(_ progress: Double, testName: String = #function, line: UInt = #line) {
        let previousProgress = StoriesProgressModel.shared.progress
        defer {
            StoriesProgressModel.shared.progress = previousProgress
        }

        StoriesProgressModel.shared.progress = progress

        assertThemedSnapshots(
            of: storyIndicator(index: 1),
            layout: layout,
            testName: testName,
            line: line
        )
    }

    @MainActor
    private func storyIndicator(index: Int) -> some View {
        StoryIndicator(index: index, style: style, progressModel: StoriesProgressModel.shared)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    }
}
#endif
