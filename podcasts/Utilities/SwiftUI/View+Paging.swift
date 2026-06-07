import SwiftUI

private struct WithScrollTargetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollTargetLayout()
    }
}

private struct WithPagingModifier: ViewModifier {
    let minPage: Int
    let maxPage: Int
    @Binding var currentPage: Int?
    let scrollProxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentPage, anchor: .leading)
    }
}

extension View {
    func withScrollTargetLayout() -> some View {
        modifier(WithScrollTargetModifier())
    }

    func withPaging(minPage: Int, maxPage: Int, currentPage: Binding<Int?>, scrollProxy: ScrollViewProxy) -> some View {
        modifier(
            WithPagingModifier(
                minPage: minPage,
                maxPage: maxPage,
                currentPage: currentPage,
                scrollProxy: scrollProxy
            )
        )
    }
}
