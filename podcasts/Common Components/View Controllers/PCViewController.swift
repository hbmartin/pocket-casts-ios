import UIKit

class PCViewController: SimpleNotificationsViewController {
    var largeTitleFont = UIFont.systemFont(ofSize: 31, weight: .bold)

    private var _customRightBtn: UIBarButtonItem?

    var customRightBtn: UIBarButtonItem? {
        get { _customRightBtn }
        set {
            _customRightBtn = newValue
            refreshRightButtons()
        }
    }

    private var _extraRightButtons: [UIBarButtonItem] = []

    var extraRightButtons: [UIBarButtonItem] {
        get { _extraRightButtons }
        set {
            _extraRightButtons = newValue
            refreshRightButtons()
        }
    }

    /// Replaces `customRightBtn`, optionally cross-fading the change via the navigation bar.
    func setCustomRightBtn(_ button: UIBarButtonItem?, animated: Bool) {
        _customRightBtn = button
        refreshRightButtons(animated: animated)
    }

    /// Replaces `extraRightButtons`, optionally cross-fading the change via the navigation bar.
    func setExtraRightButtons(_ buttons: [UIBarButtonItem], animated: Bool) {
        _extraRightButtons = buttons
        refreshRightButtons(animated: animated)
    }

    var useTransparentNavigationBarAppearance = false {
        didSet {
            setupNavBar(animated: false)
        }
    }

    private var navIconsColor: UIColor?
    private var navTitleColor: UIColor?
    private var navBgColor: UIColor?

    private var isNavBarScrolled = false

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.navigationBar.backIndicatorImage = UIImage(named: "nav-back")
        navigationController?.navigationBar.backIndicatorTransitionMaskImage = UIImage(named: "nav-back")

        navigationItem.backButtonDisplayMode = .minimal

        if customRightBtn != nil || !extraRightButtons.isEmpty {
            refreshRightButtons()
        }
        setupNavBar(animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Constants.Notifications.themeChanged, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let title, !title.isEmpty {
            setupNavBar(animated: animated)
        } else if useTransparentNavigationBarAppearance {
            // `setupNavBar` is gated on a non-empty title, but transparent-bar subclasses (which
            // often use `navigationItem.titleView` and leave `title` empty) still need the bar's
            // global appearance restored — another VC in the stack may have overwritten it.
            setTransparentNavBarScrolled(isNavBarScrolled)
        }
        refreshRightButtons()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        NotificationCenter.default.addObserver(self, selector: #selector(appWasBackgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillBecomeActive), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if customRightBtn != nil {
            navigationItem.rightBarButtonItems = nil
            navigationItem.rightBarButtonItem = nil
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        navigationController?.delegate = nil

        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    func refreshRightButtons(animated: Bool = false) {
        if !extraRightButtons.isEmpty {
            var buttons = [UIBarButtonItem]()
            if let customRightBtn {
                buttons.append(customRightBtn)
            }
            buttons.append(contentsOf: extraRightButtons)
            navigationItem.setRightBarButtonItems(buttons, animated: animated)
        } else {
            navigationItem.setRightBarButtonItems(nil, animated: animated)
            navigationItem.setRightBarButton(customRightBtn, animated: animated)
        }
    }

    func changeNavTint(titleColor: UIColor?, iconsColor: UIColor?, backgroundColor: UIColor? = nil) {
        navTitleColor = titleColor
        navIconsColor = iconsColor
        navBgColor = backgroundColor

        setupNavBar(animated: false)
    }

    func createStandardCloseButton(imageName: String) -> UIBarButtonItem {
        let closeButton = UIBarButtonItem(image: UIImage(named: imageName), style: .plain, target: nil, action: nil)
        return closeButton
    }

    @objc private func themeDidChange() {
        setupNavBar(animated: false)
        handleThemeChanged()
    }

    private func setupNavBar(animated: Bool) {
        // On iOS 26 the system Liquid Glass nav bar manages its own appearance; nothing to do.
    }

    private func configureTransparentAppearance() {
        setTransparentNavBarScrolled(isNavBarScrolled)
    }

    /// Records whether the navigation bar is at-edge or scrolled. On iOS 26, Liquid Glass handles
    /// the visual transition itself, but subclasses still call this when their scroll threshold
    /// changes so `isNavBarScrolled` stays current.
    func setTransparentNavBarScrolled(_ scrolled: Bool) {
        isNavBarScrolled = scrolled
        // On iOS 26 the system Liquid Glass nav bar handles the at-edge/scrolled transition on its
        // own, so there is nothing further to style here.
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppTheme.defaultStatusBarStyle()
    }

    @objc private func appWasBackgrounded() {
        handleAppDidEnterBackground()
    }

    @objc private func appWillBecomeActive() {
        handleAppWillBecomeActive()
    }

    func handleAppDidEnterBackground() {}
    func handleAppWillBecomeActive() {}
    func handleThemeChanged() {}

    var insetAdjuster = InsetAdjuster()
}
