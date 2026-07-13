import Combine
import PocketCastsDataModel
import SwiftUI
import UIKit

/// UIKit shell for the custom playlist editor, mirroring
/// `PlaylistPreviewViewController`: creation mode shows a bottom save button,
/// edit mode saves from the navigation bar. Saving persists the query envelope
/// and announces the change through the typed `PlaylistChanged` message.
class CustomPlaylistEditorViewController: PCViewController {
    weak var delegate: FilterCreatedDelegate?

    private let playlistName: String
    private var playlistUUID: String = ""
    private var onEditPlaylist: (() -> Void)?
    private let mode: CustomPlaylistEditorViewModel.Mode
    private(set) var viewModel: CustomPlaylistEditorViewModel!
    private var cancellables = Set<AnyCancellable>()

    private var footerView: ThemeableView! {
        didSet {
            footerView.translatesAutoresizingMaskIntoConstraints = false
            footerView.backgroundColor = AppTheme.viewBackgroundColor()
        }
    }

    private var saveButton: UIButton! {
        didSet {
            saveButton.translatesAutoresizingMaskIntoConstraints = false
            saveButton.backgroundColor = AppTheme.colorForStyle(.primaryInteractive01)
            saveButton.setTitle(L10n.playlistCustomSaveButton, for: .normal)
            saveButton.titleLabel?.font = UIFont.font(ofSize: 18.0, weight: .semibold, scalingWith: .headline)
            saveButton.titleLabel?.adjustsFontForContentSizeCategory = true
            saveButton.titleLabel?.numberOfLines = 0
            saveButton.titleLabel?.textAlignment = .center
            saveButton.tintColor = ThemeColor.primaryInteractive02()
            saveButton.layer.cornerRadius = 12
            saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        }
    }

    init(playlistName: String) {
        self.playlistName = playlistName
        self.mode = .creation
        super.init(nibName: nil, bundle: nil)
    }

    init(playlist: EpisodeFilter, onEditPlaylist: @escaping () -> Void) {
        self.playlistName = playlist.playlistName
        self.mode = .edit
        self.onEditPlaylist = onEditPlaylist
        super.init(nibName: nil, bundle: nil)
        self.playlistUUID = playlist.uuid
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        createViewModel()
        setupNavBar()
        addCloseButton()
        setupContent()
        bindSaveState()
    }

    private func createViewModel() {
        var playlist: EpisodeFilter

        switch mode {
        case .creation:
            playlist = PlaylistManager.createNewPlaylist()
            playlist.setTitle(playlistName, defaultTitle: L10n.playlistsDefaultNewPlaylist.localizedCapitalized)
            playlistUUID = playlist.uuid
        case .edit:
            if let existing = DataManager.sharedManager.findPlaylist(uuid: playlistUUID) {
                playlist = existing
            } else {
                playlist = PlaylistManager.createNewPlaylist()
                playlist.setTitle(playlistName, defaultTitle: L10n.playlistsDefaultNewPlaylist.localizedCapitalized)
                playlistUUID = playlist.uuid
            }
        }

        viewModel = CustomPlaylistEditorViewModel(draft: playlist, mode: mode)
    }

    private func setupNavBar() {
        title = playlistName
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never

        if mode == .edit {
            let saveItem = UIBarButtonItem(title: L10n.playlistCustomSave, style: .done, target: self, action: #selector(saveTapped))
            navigationItem.rightBarButtonItem = saveItem
        }
    }

    private func setupContent() {
        isModalInPresentation = true

        view.backgroundColor = AppTheme.viewBackgroundColor()

        let editor = CustomPlaylistEditorView(viewModel: viewModel).insertThemedUIView(in: self)
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.backgroundColor = .clear

        if mode == .edit {
            NSLayoutConstraint.activate([
                editor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                editor.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                editor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                editor.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else {
            footerView = ThemeableView()
            view.addSubview(footerView)

            saveButton = UIButton(type: .custom)
            footerView.addSubview(saveButton)

            NSLayoutConstraint.activate([
                footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                footerView.heightAnchor.constraint(equalTo: saveButton.heightAnchor, constant: 32),
                footerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

                saveButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 16),
                saveButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -16),
                saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

                editor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                editor.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                editor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                editor.bottomAnchor.constraint(equalTo: footerView.topAnchor)
            ])
        }
    }

    private func bindSaveState() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateSaveEnabledState()
            }
            .store(in: &cancellables)
        updateSaveEnabledState()
    }

    private func updateSaveEnabledState() {
        let canSave = viewModel.canSave && (mode == .creation || viewModel.hasChanges)
        if mode == .creation {
            saveButton?.isEnabled = canSave
            saveButton?.alpha = canSave ? 1.0 : 0.4
        } else {
            navigationItem.rightBarButtonItem?.isEnabled = canSave
        }
    }

    private func addCloseButton() {
        let closeButton = createStandardCloseButton(imageName: "cancel")
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        navigationItem.leftBarButtonItem = closeButton
    }

    @objc private func closeTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func saveTapped() {
        guard let envelope = viewModel.envelopeForSaving() else { return }

        var playlist = viewModel.draft
        playlist.customQuery = envelope
        playlist.syncStatus = SyncStatus.notSynced.rawValue
        playlist.isNew = false

        if mode == .creation {
            DataManager.sharedManager.bumpSortPositionForAllPlaylists()
            let firstSortPosition = max(0, DataManager.sharedManager.firstSortPositionForPlaylist() - 1)
            playlist.sortPosition = Int32(firstSortPosition)
        }

        let savedPlaylist = DataManager.sharedManager.save(playlist: playlist)
        viewModel.draft = savedPlaylist

        NotificationCenter.postOnMainThread(PlaylistChanged(playlist: savedPlaylist))

        switch mode {
        case .creation:
            UserDefaults.standard.set(savedPlaylist.uuid, forKey: Constants.UserDefaults.lastFilterShown)
            delegate?.filterCreated(newFilter: savedPlaylist)
            Analytics.track(.filterCreated, properties: [
                "custom": true,
                "custom_mode": viewModel.editorMode.rawValue
            ])
            delegate?.presentingPlaylistDetail = true
            // Dismiss both the editor and the creation screen underneath it.
            presentingViewController?.presentingViewController?.dismiss(animated: true, completion: nil)
        case .edit:
            Analytics.track(.filterUpdated, properties: [
                "group": "custom_query",
                "source": "filters",
                "custom": true,
                "custom_mode": viewModel.editorMode.rawValue
            ])
            onEditPlaylist?()
            presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
}

/// SwiftUI root for the editor: the Builder/SQL mode switch, the active editor,
/// and the device-local footer.
struct CustomPlaylistEditorView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var viewModel: CustomPlaylistEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.playlistCustomModeBuilder, selection: $viewModel.editorMode) {
                ForEach(CustomPlaylistEditorViewModel.EditorMode.allCases) { editorMode in
                    Text(editorMode.displayName).tag(editorMode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            switch viewModel.editorMode {
            case .builder:
                CustomQueryBuilderView(viewModel: viewModel)
            case .sql:
                CustomQuerySQLView(viewModel: viewModel)
            }

            Spacer(minLength: 0)

            Text(L10n.playlistCustomOnlyOnDeviceFooter)
                .font(.footnote)
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .background(AppTheme.color(for: .primaryUi04, theme: theme))
    }
}
