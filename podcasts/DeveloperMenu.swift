import SwiftUI
import PocketCastsServer
import PocketCastsDataModel
import PocketCastsUtils
import UniformTypeIdentifiers

struct DeveloperMenu: View {
    @State var showingImporter = false
    @State var showingExporter = false
    @State var showingPlaylistsOnboarding = false
    @State var showingRecommendationsOnboarding = false
    @State var showingInterestsOnboarding = false
    @State var showingRecommendationsOnboardingSelected = false
    @State var showIntroCarousel = false
    @State var showingNotificationsPermissions = false
    @State var enableDebugPlaylistLimit = false
    @State var showingResetConfirmation = false

    @StateObject var recommendationsViewModel = RecommendationsViewModel(configuration: .all)

    var body: some View {
        List {
            Section {
                Button(action: {
                    showingImporter.toggle()
                }, label: {
                    Text("Import Bundle")
                })
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pcasts]) { result in
                    switch result {
                    case .success(let url):
                        Task {
                            do {
                                try DeveloperBundleImporter.importBundle(from: url)
                            } catch let error as DeveloperBundleImportError {
                                FileLog.shared.addMessage(error.logMessage)
                            } catch {
                                FileLog.shared.addMessage("DeveloperMenu: failed to import selected bundle")
                            }
                        }
                    case .failure:
                        FileLog.shared.addMessage("DeveloperMenu: file picker failed")
                    }
                }
                Button(action: {
                    showingExporter.toggle()
                }, label: {
                    Text("Export Bundle")
                })
                .fileExporter(isPresented: $showingExporter, document: PCBundleDoc()) { result in
                    switch result {
                    case .success(let url):
                        FileLog.shared.addMessage("DeveloperMenu: saved to \(url)")
                    case .failure(let error):
                        FileLog.shared.addMessage("DeveloperMenu: failed to export pcasts: \(error)")
                    }
                }
                Button(role: .destructive, action: {
                    showingResetConfirmation = true
                }, label: {
                    Text("Reset Database + Settings")
                })
                .alert("Reset Database + Settings?", isPresented: $showingResetConfirmation) {
                    Button("Reset and Quit", role: .destructive) {
                        PCBundleDoc.delete()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently deletes the local database and all settings, then quits the app. This cannot be undone.")
                }
            }
            Section {
                Button(action: {
                    UIPasteboard.general.string = ServerSettings.pushToken()
                }, label: {
                    Text("Copy Push Token")
                })

                Button(action: {
                    UIPasteboard.general.string = ServerConfig.shared.syncDelegate?.uniqueAppId()
                }, label: {
                    Text("Copy Device ID")
                })
            }

            Section {
                Button("Corrupt Sync Login Token") {
                    ServerSettings.syncingV2Token = "badToken"
                }

                Button("Force Reload Discover") {
                    DiscoverServerHandler.shared.discoveryCache.removeAllCachedResponses()
                    URLSession.shared.configuration.urlCache?.removeAllCachedResponses()
                    NotificationCenter.postOnMainThread(ChartRegionChanged())
                }

                Button("Unsubscribe from all Podcasts") {
                    let podcasts = DataManager.sharedManager.allPodcasts(includeUnsubscribed: false)

                    for podcast in podcasts {
                        PodcastManager.shared.unsubscribe(podcast: podcast)
                    }
                }

                Button("Clear all folder information") {
                    DataManager.sharedManager.clearAllFolderInformation()
                }
            }

            Section {
                Button("Reset Informational Modal Visibility") {
                    Settings.shouldShowInitialOnboardingFlow = true
                    Settings.hasShownInformationalViewModal = false
                }
                Button("Reset banners visibility") {
                    InformationalBannerType.allCases.forEach {
                        UserDefaults.standard.set(false, forKey: "kInformational\($0.rawValue.capitalized)Banner")
                    }
                }
            } header: {
                Text("Encourage Account Creation Banners")
            }

            Section {
                Button("Reset CTA conditions") {
                    Settings.suggestedFoldersUpsellCount = 0
                    Settings.suggestedFoldersLastUpsellDate = nil
                }
            } header: {
                Text("Suggested Folders")
            }

            Section {
                Button("Notifications Permissions Screen") {
                    showingNotificationsPermissions.toggle()
                }.sheet(isPresented: $showingNotificationsPermissions) {
                    NotificationsPermissionsView()
                }
                Button("Speed Up Notifications") {
                    NotificationsGroup.speedUpNotifications = true
                }
                Button("Log Schedule") {
                    NotificationsCoordinator.shared.debugMode = true
                }
            } header: {
                Text("Notifications")
            }

            Section {
                Button("Show Intro Carousel") {
                    showIntroCarousel = true
                }
                .sheet(isPresented: $showIntroCarousel) {
                    IntroCarouselView(coordinator: LoginCoordinator())
                }
                Button("Show Onboarding Recommendations") {
                    showingRecommendationsOnboarding = true
                }
                .sheet(isPresented: $showingRecommendationsOnboarding) {
                    NavigationStack {
                        OnboardingRecommendationsView(coordinator: LoginCoordinator())
                            .environmentObject(Theme.sharedTheme)
                    }
                }
                Button("Show Onboarding Interests") {
                    showingInterestsOnboarding = true
                }
                .sheet(isPresented: $showingInterestsOnboarding) {
                    InterestsView(continueCallback: { categories in
                        showInterestRecommendations(categories: categories)
                    }, notNowCallback: {
                        showingInterestsOnboarding.toggle()
                    }, isInsideNavigation: false)
                        .environmentObject(Theme.sharedTheme)
                }
                .sheet(isPresented: $showingRecommendationsOnboardingSelected) {
                    OnboardingRecommendationsView(coordinator: LoginCoordinator(), viewModel: self.recommendationsViewModel)
                        .environmentObject(Theme.sharedTheme)
                }
            } header: {
                Text("Onboarding")
            }

            Section {
                Toggle(isOn: $enableDebugPlaylistLimit) {
                    Text("Enable Debug Playlists limit")
                }
                .onChange(of: enableDebugPlaylistLimit) { _, newValue in
                    Settings.debugPlaylistsLimit = newValue ? 6 : Constants.Limits.maxFilterItems
                }
                Button("Show Playlists Onboarding") {
                    showingPlaylistsOnboarding = true
                }
                .sheet(isPresented: $showingPlaylistsOnboarding) {
                    PlaylistsOnboardingView(onClose: {
                        showingPlaylistsOnboarding = false
                    })
                }
            } header: {
                Text("Playlist Rebranding")
            }
            Section {
                Text(Bundle.main.identifier)
            } header: {
                Text("Bundle ID")
            }
        }
    }

    func showInterestRecommendations(categories: [DiscoverCategory]) {
        showingInterestsOnboarding = false
        recommendationsViewModel.configuration = .preselected(categories)
        showingRecommendationsOnboardingSelected = true
    }
}

enum DeveloperBundleImportError: Error, Equatable {
    case accessDenied
    case fileReadFailed
    case importFailed

    var logMessage: String {
        switch self {
        case .accessDenied:
            "DeveloperMenu: failed to access selected bundle"
        case .fileReadFailed:
            "DeveloperMenu: failed to read selected bundle"
        case .importFailed:
            "DeveloperMenu: failed to apply selected bundle"
        }
    }
}

enum DeveloperBundleImporter {
    static func importBundle(
        from url: URL,
        startAccessing: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccessing: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        readFileWrapper: (URL) throws -> FileWrapper = { try FileWrapper(url: $0, options: .immediate) },
        performImport: (FileWrapper) throws -> Void = { try PCBundleDoc.performImport(from: $0) }
    ) throws {
        guard startAccessing(url) else {
            throw DeveloperBundleImportError.accessDenied
        }

        // A successful PCBundleDoc import terminates the app. Eagerly load the
        // wrapper and release scoped access before applying it so stop always runs.
        let fileWrapper: FileWrapper
        do {
            defer { stopAccessing(url) }
            fileWrapper = try readFileWrapper(url)
        } catch {
            throw DeveloperBundleImportError.fileReadFailed
        }

        do {
            try performImport(fileWrapper)
        } catch {
            throw DeveloperBundleImportError.importFailed
        }
    }
}

struct DeveloperMenu_Previews: PreviewProvider {
    static var previews: some View {
        DeveloperMenu()
    }
}

extension Bundle {

    var identifier: String {
        guard let infoDictionary, let identifier = infoDictionary["CFBundleIdentifier"] as? String else {
            return "Cound not load bundle id."
        }

        return identifier
    }
}
