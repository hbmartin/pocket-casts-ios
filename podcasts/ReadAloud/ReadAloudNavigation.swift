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

        let libraryView = ReadAloudLibraryView(onImportTapped: { [weak self] in
            self?.presentDocumentPicker()
        })
        embed(PCHostingController(rootView: libraryView.setupDefaultEnvironment()))
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
        let model = ReadAloudImportViewModel(source: .file(url, sourceKind))
        let box = DismissBox()
        let view = ReadAloudImportView(
            model: model,
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
