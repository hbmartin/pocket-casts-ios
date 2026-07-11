import SwiftUI

/// Shows the default profile image view.
struct ProfileImage: View {
    @EnvironmentObject var theme: Theme
    let email: String?

    var body: some View {
        defaultProfileView
    }

    private var defaultProfileView: some View {
        ZStack {
            theme.primaryUi05
            Image("profileAvatar")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .foregroundColor(theme.primaryUi01)
                .padding()
        }
    }
}
