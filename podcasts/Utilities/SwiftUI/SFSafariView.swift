import SafariServices
import SwiftUI
import UIKit

struct SFSafariView: UIViewControllerRepresentable {
    let url: URL
    let context: URLHelper.InAppBrowserContext

    func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> SFSafariViewController {
        guard let safariViewController = URLHelper.makeInAppBrowser(for: url, context: self.context) else {
            preconditionFailure("SFSafariView requires a URL allowed for in-app browser presentation")
        }

        return safariViewController
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SFSafariView>) {
        // No need to do anything here
    }
}

struct SFSafariViewModifier: ViewModifier {
    @State private var presentationState: URLPresentationState = .notPresented

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { incomingURL in
                switch URLHelper.inAppBrowserDecision(for: incomingURL, context: .externalContent) {
                case .inAppBrowser:
                    presentationState = .presenting(incomingURL)
                    return .handled
                case .externalApplication:
                    UIApplication.shared.open(incomingURL, options: [:], completionHandler: nil)
                    return .handled
                case .blocked, .authenticationSessionRequired:
                    return .discarded
                }
            })
            .sheet(isPresented: Binding(
                get: { presentationState != .notPresented },
                set: { if !$0 { presentationState = .notPresented } }
            )) {
                if case .presenting(let url) = presentationState {
                    SFSafariView(url: url, context: .externalContent)
                        .onAppear {
                            print("Opening URL: \(url)")
                        }
                }
            }
    }

    enum URLPresentationState: Equatable {
        case notPresented
        case presenting(URL)
    }
}

extension View {
    /// Handles all `OpenURLAction` events from `EnvironmentValues.openURL` with `SFSafariView` (a SwiftUI wrapper for`SafariViewController`).
    func handleURLsWithSFSafariView() -> some View {
        self.modifier(SFSafariViewModifier())
    }
}
