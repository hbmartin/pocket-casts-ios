import Foundation

class LogsViewController: ThemedHostingController<LogsView> {
    init() {
        let model = LogsViewModel()
        let screen = LogsView(model: model)
        super.init(rootView: screen)
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .clear
    }
}
