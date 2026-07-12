import SwiftUI
import PocketCastsUtils

struct SubscriptionProfileImage: View {
    @ObservedObject var viewModel: ProfileDataViewModel
    @State private var shareProfilePhoto: UIImage?

    var body: some View {
        Group {
            if let photo = shareProfilePhoto {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProfileImage(email: viewModel.profile.email)
            }
        }
        .clipShape(Circle())
        .task {
            shareProfilePhoto = ShareProfileViewModel.loadSavedProfilePhoto()
            for await _ in NotificationCenter.default.notifications(named: ShareProfileViewModel.photoDidChangeNotification) {
                shareProfilePhoto = ShareProfileViewModel.loadSavedProfilePhoto()
            }
        }
    }
}

struct SubscriptionProfileImage_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionProfileImage(viewModel: .init())
    }
}
