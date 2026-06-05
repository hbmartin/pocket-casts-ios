import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject var viewModel: WelcomeViewModel

    private var titleText: String {
        L10n.welcomeNewAccountTitle
    }

    var body: some View {
        ZStack(alignment: .top) {
            WelcomeConfetti(type: .normal)

            ScrollViewIfNeeded {
                VStack(alignment: .leading) {
                    HeaderIcon()
                    Label(titleText, for: .title)
                        .padding(.top, 28)
                        .padding(.bottom, 24)

                    VStack(spacing: 16) {
                        ForEach(viewModel.sections) { section in
                            WelcomeSectionView(model: model(for: section)) {
                                viewModel.sectionTapped(section)
                            }
                        }
                    }

                    Spacer()

                    Button(L10n.done) {
                        viewModel.doneTapped()
                    }.buttonStyle(RoundedButtonStyle(theme: theme))
                }
                .padding([.leading, .trailing], Config.padding.horizontal)
                .padding(.top, Config.padding.top)
                .padding(.bottom)
            }
            .background(AppTheme.color(for: .background, theme: theme).ignoresSafeArea())
        }
    }

    private func model(for section: WelcomeViewModel.WelcomeSection) -> WelcomeSectionModel {
        switch section {

        case .importPodcasts:
            return WelcomeSectionModel(title: L10n.welcomeImportTitle, subtitle: L10n.welcomeImportDescription, imageName: "welcome-import", buttonTitle: L10n.welcomeImportButton)
        case .podcasts:
            return WelcomeSectionModel(title: L10n.podcastsPlural, subtitle: L10n.profileListeningHistoryEmptyDescription, imageName: "welcome-discover", buttonTitle: L10n.podcastListGoToPodcastsAction)
        }
    }
}

private extension ThemeStyle {
    static let background = Self.primaryUi01
    static let text = Self.primaryText01
    static let sectionDescription = Self.primaryText02
    static let icon = Self.primaryIcon01
    static let sectionStroke = Self.primaryUi05
    static let sectionButtonTitle = Self.primaryInteractive01
}

private enum Config {
    enum padding {
        static let top = 40.0
        static let horizontal = 24.0
        static let sectionButtonVertical = 16.0
    }

    static let sectionCornerRadius = 12.0
}

// MARK: - Preview
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(viewModel: WelcomeViewModel(navigationController: UINavigationController(), displayType: .newAccount))
            .previewWithAllThemes()
    }
}

// MARK: - View Components
struct WelcomeConfetti: View {
    let type: WelcomeConfettiEmitter.ConfettiType

    var body: some View {
        GeometryReader { proxy in
            WelcomeConfettiEmitter(type: type, frame: proxy.frame(in: .local)).ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea().zIndex(1000)
    }
}

/// A view that displays the header icon
/// We display this using 2 images to allow us to apply the color overlay to the
/// icon without effecting the check mark
private struct HeaderIcon: View {
    @EnvironmentObject var theme: Theme

    var body: some View {
        HStack {
            ZStack {
                Image("welcome-icon")
                    .foregroundColor(AppTheme.color(for: .icon, theme: theme))
                Image("welcome-icon-check")
            }
            Spacer()
        }
    }
}

private struct Label: View {
    @EnvironmentObject var theme: Theme

    enum LabelStyle {
        case title
        case sectionTitle
        case sectionDescription
    }

    let text: String
    let labelStyle: LabelStyle

    init(_ text: String, for style: LabelStyle) {
        self.text = text
        self.labelStyle = style
    }

    var body: some View {
        Text(text)
            .foregroundColor(textColor)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(LabelFont(labelStyle: labelStyle))
    }

    private var textColor: Color {
        switch labelStyle {

        case .title:
            return AppTheme.color(for: .text, theme: theme)
        case .sectionTitle:
            return AppTheme.color(for: .text, theme: theme)
        case .sectionDescription:
            return AppTheme.color(for: .sectionDescription, theme: theme)
        }
    }

    private struct LabelFont: ViewModifier {
        let labelStyle: LabelStyle

        func body(content: Content) -> some View {
            switch labelStyle {
            case .title:
                return content.font(size: 31, style: .title, weight: .bold, maxSizeCategory: .extraExtraLarge)
            case .sectionTitle:
                return content.font(size: 18, style: .body, weight: .semibold, maxSizeCategory: .extraExtraExtraLarge)
            case .sectionDescription:
                return content.font(size: 13, style: .caption, maxSizeCategory: .extraExtraExtraLarge)
            }
        }
    }
}

private struct WelcomeSectionModel {
    let title: String
    let subtitle: String
    let imageName: String
    let buttonTitle: String
}

private struct WelcomeSectionView: View {
    @EnvironmentObject var theme: Theme

    let model: WelcomeSectionModel
    let action: () -> Void

    var body: some View {
        // The container view that displays the stroke
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 0) {

                // The labels + icon view
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(model.title, for: .sectionTitle)
                        Label(model.subtitle, for: .sectionDescription)
                    }
                    Spacer()
                    Image(model.imageName)
                        .foregroundColor(AppTheme.color(for: .icon, theme: theme))
                }.padding(Config.padding.horizontal)

                divider
                button
            }
        }.overlay(roundedCorners)
    }

    private var roundedCorners: some View {
        RoundedRectangle(cornerRadius: Config.sectionCornerRadius)
            .stroke(AppTheme.color(for: .sectionStroke, theme: theme), lineWidth: 1)
    }

    private var divider: some View {
        Divider().background(
            AppTheme.color(for: .sectionStroke, theme: theme)
        )
    }

    private var button: some View {
        Button(model.buttonTitle) {
            action()
        }
        .buttonStyle(SectionButton(theme: theme))
    }
}

private struct SectionButton: ButtonStyle {
    @ObservedObject var theme: Theme
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .foregroundColor(AppTheme.color(for: .sectionButtonTitle, theme: theme))
        .font(size: 15, style: .callout, weight: .medium, maxSizeCategory: .extraExtraExtraLarge)
        .padding([.top, .bottom], Config.padding.sectionButtonVertical)
        .padding([.leading, .trailing], Config.padding.horizontal)
        .contentShape(Rectangle())
        .applyButtonEffect(isPressed: configuration.isPressed)
    }
}

// MARK: - Confetti 🎉

struct WelcomeConfettiEmitter: UIViewRepresentable {
    let type: ConfettiType
    let frame: CGRect
    let afterDelay: TimeInterval

    enum ConfettiType {
        case normal
        case plus
    }

    init(type: ConfettiType, frame: CGRect, afterDelay: TimeInterval = 0.5) {
        self.type = type
        self.frame = frame
        self.afterDelay = afterDelay
    }

    func makeUIView(context: Context) -> UIView {
        let hostView = UIView(frame: frame)

        DispatchQueue.main.asyncAfter(deadline: .now() + afterDelay) {
            let completion: ConfettiView.AnimationCompletion = { confettiView in
                confettiView.removeFromSuperview()
            }

            let confetti = (type == .plus) ? PlusConfettiView.self : NormalConfettiView.self
            confetti.cleanupAndAnimate(on: hostView, frame: frame, onAnimationCompletion: completion)
        }

        return hostView
    }

    func updateUIView(_ uiView: UIView, context: Context) { }

    private class PlusConfettiView: ConfettiView {
        override func emitConfetti() {
            guard let icon = UIImage(named: "confetti-plus") else {
                return
            }

            // Add more to the emitter
            var particles: [Particle] = []
            for _ in 0..<10 {
                particles.append(Particle(image: icon))
            }

            var config = PlusConfettiView.EmitterConfig()
            config.scaleRange = 1.2

            self.emit(with: particles, config: config)
        }
    }

    private class NormalConfettiView: ConfettiView {
        override func emitConfetti() {
            var images: [Particle] = []

            // Generate the particles
            for i in 1..<21 {
                let fileName = "confetti-shape-\(i)"
                if let image = UIImage(named: fileName) {
                    images.append(Particle(image: image))
                }
            }

            self.emit(with: images, config: NormalConfettiView.EmitterConfig())
        }
    }
}
