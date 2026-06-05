import SwiftUI
import SafariServices
import EndOfYear

struct SlumberWhatsNewHeader: View {
    @State var distance: CGFloat = 0

    var body: some View {
        HStack {
            Group {
                PodcastCover(podcastUuid: "82e37e80-755d-0138-eddc-0acc26574db2")
                    .offset(y: distance)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: distance)
                PodcastCover(podcastUuid: "9478cc80-7c42-0138-edfe-0acc26574db2")
                    .offset(y: distance)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(0.4), value: distance)
                PodcastCover(podcastUuid: "37082d70-e945-0137-b6eb-0acc26574db2")
                    .offset(y: distance)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(0.8), value: distance)
                PodcastCover(podcastUuid: "62200ab0-b7ec-0139-f606-0acc26574db2")
                    .offset(y: distance)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(1.2), value: distance)
            }
                .frame(width: 120, height: 120)
        }
        .onAppear {
            distance = 30
        }
            .environment(\.renderForSharing, false)
    }
}

struct SlumberCustomBody: View {
    @EnvironmentObject var theme: Theme

    @ObservedObject private var viewModel = SlumberAnnouncementViewModel()

    var body: some View {
        Text(L10n.announcementSlumberTitle)
            .font(style: .title, weight: .bold)
            .foregroundStyle(theme.primaryText01)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
        UnderlineLinkTextView(viewModel.message)
            .font(style: .body)
            .foregroundStyle(theme.primaryText01)
            .tint(theme.primaryInteractive01)
            .multilineTextAlignment(.center)
            .padding(.bottom)
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture {
                UIPasteboard.general.string = Settings.slumberPromoCode
                Toast.show(L10n.announcementSlumberCodeCopied)
            }

        Button(viewModel.buttonTitle) {
            Analytics.track(.whatsnewConfirmButtonTapped)

            viewModel.showRedeem()
        }
        .buttonStyle(RoundedButtonStyle(theme: theme))
        .padding(.top, 40)
        .padding(.bottom, 15)
    }
}

class SlumberAnnouncementViewModel: ObservableObject {
    @Published var buttonTitle: String = L10n.announcementSlumberRedeem
    @Published var message: String = SlumberAnnouncementViewModel.description

    private static var description: String {
        let code = Settings.slumberPromoCode ?? ""
        return L10n.announcementSlumberDescription("**\(code)**")
            .replacingOccurrences(of: L10n.announcementSlumberDescriptionLearnMore,
                                   with: "[\(L10n.announcementSlumberDescriptionLearnMore)](https://slumberstudios.com)")
    }

    func showRedeem() {
        guard let parentController = SceneHelper.rootViewController(), let url = URL(string: "https://slumberstudios.com/pocketcasts/") else { return }

        let safariController = SFSafariViewController(with: url)
        safariController.modalPresentationStyle = .formSheet
        parentController.present(safariController, animated: true)
    }
}

#Preview {
    SlumberWhatsNewHeader()
}
