import SwiftUI

class BottomSheetSwiftUIWrapper<ContentView: View>: UIViewController, UISheetPresentationControllerDelegate {
    private let stackView = UIStackView()
    private var customDetentHeight: CGFloat = 0
    private weak var hostingController: UIHostingController<AnyView>?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    private let backgroundColor: UIColor?
    private let backgroundStyle: ThemeStyle?
    private let dismissCallback: (() -> Void)?

    init(rootView content: ContentView, backgroundColor: UIColor, dismissCallback: (() -> Void)? = nil) {
        self.backgroundColor = backgroundColor
        backgroundStyle = nil
        self.dismissCallback = dismissCallback
        super.init(nibName: nil, bundle: nil)

        setup(content: content, backgroundColor: backgroundColor)
    }

    init(rootView content: ContentView, backgroundStyle: ThemeStyle = .primaryUi01, dismissCallback: (() -> Void)? = nil) {
        self.backgroundStyle = backgroundStyle
        backgroundColor = nil
        self.dismissCallback = dismissCallback
        super.init(nibName: nil, bundle: nil)

        setup(content: content, backgroundStyle: backgroundStyle)
    }

    private func setup(content: ContentView, backgroundStyle: ThemeStyle? = nil, backgroundColor: UIColor? = nil) {
        registerForPreferredContentSizeCategoryChanges { wrapperController in
            guard let sheetController = wrapperController.sheetPresentationController else { return }

            wrapperController.updatePreferredContentSize()
            DispatchQueue.main.async {
                sheetController.animateChanges {
                    sheetController.invalidateDetents()
                }
            }
        }

        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let hostingController = UIHostingController(
            rootView: AnyView(content
                .edgesIgnoringSafeArea(.all)
                .environmentObject(Theme.sharedTheme))
        )
        hostingController.sizingOptions = [.intrinsicContentSize]
        addChild(hostingController)
        stackView.addArrangedSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        if let backgroundStyle {
            hostingController.view.backgroundColor = AppTheme.colorForStyle(backgroundStyle)
        } else if let backgroundColor {
            hostingController.view.backgroundColor = backgroundColor
        }

        updatePreferredContentSize()
    }

    private func updatePreferredContentSize() {
        hostingController?.view.layoutIfNeeded()
        stackView.layoutIfNeeded()

        let fittingSize = stackView.systemLayoutSizeFitting(
            CGSize(width: UIScreen.main.bounds.width, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )

        customDetentHeight = fittingSize.height
        preferredContentSize = CGSize(width: fittingSize.width, height: fittingSize.height)
    }

    override func loadView() {
        if let backgroundStyle {
            let themeView = ThemeableView()
            themeView.style = backgroundStyle
            view = themeView
        } else if let backgroundColor {
            view = UIView()
            view.backgroundColor = backgroundColor
        }

        view.alpha = 0
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePreferredContentSize()
        view.alpha = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func present(_ content: ContentView, autoSize: Bool = false, showingGrabber: Bool = false, in viewController: UIViewController, dismissCallback: (() -> Void)? = nil) {
        let wrapperController = BottomSheetSwiftUIWrapper(rootView: content, dismissCallback: dismissCallback)
        var previousSizeCategory = viewController.traitCollection.preferredContentSizeCategory
        if autoSize {
            let customDetent = UISheetPresentationController.Detent.custom { context in
                if context.containerTraitCollection.preferredContentSizeCategory != previousSizeCategory {
                    previousSizeCategory = context.containerTraitCollection.preferredContentSizeCategory
                    wrapperController.updatePreferredContentSize()
                }
                return wrapperController.customDetentHeight
            }
            wrapperController.presentModally(in: viewController, detents: [customDetent], showingGrabber: showingGrabber)
        } else {
            wrapperController.presentModally(in: viewController, showingGrabber: showingGrabber)
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        dismissCallback?()
    }
}

private extension UIViewController {
    func presentModally(
        in viewController: UIViewController,
        detents: [UISheetPresentationController.Detent] = [.medium()],
        showingGrabber: Bool = false
    ) {
        if let sheetController = sheetPresentationController {
            sheetController.detents = detents
            if let sheetDelegate = self as? UISheetPresentationControllerDelegate {
                sheetController.delegate = sheetDelegate
            }
            sheetController.prefersGrabberVisible = showingGrabber
            sheetController.preferredCornerRadius = LiquidGlass.isEnabled ? 26 : 10

            // Prevent sheet from being dismissed by dragging down
            sheetController.prefersScrollingExpandsWhenScrolledToEdge = false
        }

        viewController.present(self, animated: true, completion: nil)
    }
}
