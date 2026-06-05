import SafariServices
import UIKit
import WebKit

func directSafariPresentation(url: URL) {
    // ruleid: pocketcasts.direct-sfsafariviewcontroller
    _ = SFSafariViewController(with: url)
}

func helperTrustedDocumentation(url: URL, presenter: UIViewController) {
    // ok: pocketcasts.direct-sfsafariviewcontroller
    URLHelper.open(url, context: .trustedDocumentation, from: presenter)
}

func helperExternalContent(url: URL, presenter: UIViewController) {
    // ok: pocketcasts.direct-sfsafariviewcontroller
    URLHelper.open(url, context: .externalContent, from: presenter)
}

func login(url: URL, presenter: UIViewController) {
    // ruleid: pocketcasts.sensitive-auth-requires-aswebauthenticationsession
    URLHelper.open(url, context: .sensitiveAuth, from: presenter)
}

func navigationActionDirectLoad(webView: WKWebView, navigationAction: WKNavigationAction) {
    // ruleid: pocketcasts.webview-navigation-action-without-urlhelper
    webView.load(URLRequest(url: navigationAction.request.url))
}
