import SwiftUI
import PocketCastsUtils

struct AccountHeaderView: View {
    @ObservedObject var viewModel: AccountHeaderViewModel

    var body: some View {
        container { _ in
            VStack(spacing: FeatureFlag.newOnboardingUpgrade.enabled ? 8 : Constants.padding.vertical) {
                SubscriptionProfileImage(viewModel: viewModel)
                    .frame(width: Constants.imageSize, height: Constants.imageSize)
                ProfileInfoLabels(profile: viewModel.profile, alignment: .center, spacing: Constants.spacing)
            }
        }
    }

    // MARK: - Private: Wrapper Views
    @ViewBuilder
    /// Main content wrapper view that renders the rest of the content
    private func container<Content: View>(@ViewBuilder _ content: @escaping (GeometryProxy) -> Content) -> some View {
        ContentSizeGeometryReader { proxy in
            VStack(spacing: Constants.spacing) {
                content(proxy)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, Constants.padding.top)
            .padding(.bottom, Constants.padding.bottom)
            .padding(.horizontal, Constants.padding.horizontal)
        } contentSizeUpdated: { size in
            viewModel.contentSizeChanged(size)
        }
    }

    // MARK: - View Constants
    private enum Constants {
        static let spacing = 16.0
        static let imageSize = 64.0

        enum padding {
            static let top = 30.0
            static let bottom = 16.0
            static let horizontal = 16.0

            static let vertical = 14.0
        }
    }
}

// MARK: - Previews
struct AccountHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            AccountHeaderView(viewModel: .init())

            Spacer()
        }.setupDefaultEnvironment()
    }
}
