import PocketCastsDataModel
import PocketCastsReadAloud
import SwiftUI
import UIKit

/// Hosts the Read Aloud library and owns the document picker on its behalf.
///
/// A container rather than a bare `PCHostingController` because the picker is
/// UIKit and needs a presenting view controller and a delegate; the SwiftUI view
/// just calls a closure.
@MainActor
final class ReadAloudLibraryViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.readAloudLibraryTitle

        let libraryView = ReadAloudLibraryView(
            onImportTapped: { [weak self] in self?.presentDocumentPicker() },
            onComposeTapped: { [weak self] in self?.presentCompose() }
        )
        embed(PCHostingController(rootView: libraryView.setupDefaultEnvironment()))
    }

    private func presentCompose() {
        ReadAloudNavigation.presentCompose(from: self)
    }

    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: ReadAloudFileTypes.pickerTypes,
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
}

extension ReadAloudLibraryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        ReadAloudNavigation.presentImport(for: url, sourceKind: .picked, from: self)
    }
}

/// Hosts the Read Aloud settings screen, which pushes the library.
@MainActor
final class ReadAloudSettingsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.readAloudTitle

        let settingsView = ReadAloudSettingsView(onLibraryTapped: { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(ReadAloudLibraryViewController(), animated: true)
        })
        embed(PCHostingController(rootView: settingsView.setupDefaultEnvironment()))
    }
}

@MainActor
enum ReadAloudNavigation {
    /// Presents the import sheet for a picked or shared file.
    static func presentImport(for url: URL, sourceKind: NarrationSourceKind, from viewController: UIViewController) {
        presentImport(source: .file(url, sourceKind), from: viewController)
    }

    /// Presents the compose screen, then the review sheet for what was written.
    ///
    /// The review sheet replaces the compose sheet rather than stacking on it:
    /// two modals deep is where a Cancel button stops meaning anything obvious.
    static func presentCompose(from viewController: UIViewController) {
        let box = DismissBox()
        let composeView = ReadAloudComposeView(
            onCancel: { box.controller?.dismiss(animated: true) },
            onNext: { preview in
                guard let host = box.controller, let presenter = host.presentingViewController else { return }
                host.dismiss(animated: true) {
                    presentImport(source: .composed(preview), from: presenter)
                }
            }
        )
        let controller = PCHostingController(rootView: composeView.setupDefaultEnvironment())
        box.controller = controller
        viewController.present(controller, animated: true)
    }

    /// Presents the review sheet for an already-resolved source.
    static func presentImport(source: ReadAloudImportViewModel.Source, from viewController: UIViewController) {
        let box = DismissBox()
        let view = ReadAloudImportView(
            model: ReadAloudImportViewModel(source: source),
            onFinished: { box.controller?.dismiss(animated: true) },
            onCancel: { box.controller?.dismiss(animated: true) }
        )
        let controller = PCHostingController(rootView: view.setupDefaultEnvironment())
        box.controller = controller
        viewController.present(controller, animated: true)
    }

    /// Lets the sheet dismiss itself without the view holding its own host.
    @MainActor
    private final class DismissBox {
        weak var controller: UIViewController?
    }
}

private extension UIViewController {
    /// Adds a hosting controller as a full-bleed child.
    func embed(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        child.didMove(toParent: self)
    }
}
