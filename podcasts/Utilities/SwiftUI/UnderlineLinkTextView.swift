import SwiftUI

struct UnderlineLinkTextView: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        var attributedString = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        attributedString.runs.filter({ $0.link != nil }).forEach({ run in
            attributedString[run.range].underlineStyle = .init(pattern: .solid)
        })
        let textView = Text(attributedString)

        // Open the link inside the app
        return textView.environment(\.openURL, OpenURLAction { url in
            guard URLHelper.open(
                url,
                context: .externalContent,
                options: .init(modalPresentationStyle: .formSheet)
            ) != nil else {
                return URLHelper.inAppBrowserDecision(for: url, context: .externalContent) == .blocked ? .discarded : .handled
            }

            return .handled
        })
    }
}

#Preview {
    VStack {
        UnderlineLinkTextView("Hello **World**!")
        UnderlineLinkTextView("Hel[lo, Wor](https://pocketcasts.com)ld!")
        UnderlineLinkTextView("[Hello](https://pocketcasts.com), World!")
        UnderlineLinkTextView("Hello, [World](https://pocketcasts.com)!")
        UnderlineLinkTextView("I have [multiple](https://pocketcasts.com) [links](https://pocketcasts.com)!")
        UnderlineLinkTextView("Look [how](https://pocketcasts.com) cool [I](https://pocketcasts.com) [am](https://pocketcasts.com)! :)")
    }
}
