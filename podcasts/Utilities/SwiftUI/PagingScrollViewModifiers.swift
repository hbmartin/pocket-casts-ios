import SwiftUI

struct WithScrollTargetModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollTargetLayout()
        } else {
            content
        }
    }
}

struct WithPagingModifier: ViewModifier {
    let minPage: Int
    let maxPage: Int
    @Binding var currentPage: Int?
    let scrollProxy: ScrollViewProxy

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $currentPage, anchor: .leading)
        } else {
            content.scrollDisabled(true)
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < 0 {
                            currentPage = min(maxPage, (currentPage ?? 0) + 1)
                        }

                        if value.translation.width > 0 {
                            currentPage = max(minPage, (currentPage ?? 0) - 1)
                        }
                    })
                .onChange(of: currentPage) { newValue in
                    withAnimation {
                        scrollProxy.scrollTo(newValue, anchor: .leading)
                    }
                }
        }
    }
}

extension View {
    func withScrollTargetLayout() -> some View {
        modifier(WithScrollTargetModifier())
    }

    func withPaging(minPage: Int, maxPage: Int, currentPage: Binding<Int?>, scrollProxy: ScrollViewProxy) -> some View {
        modifier(WithPagingModifier(minPage: minPage, maxPage: maxPage, currentPage: currentPage, scrollProxy: scrollProxy))
    }
}
