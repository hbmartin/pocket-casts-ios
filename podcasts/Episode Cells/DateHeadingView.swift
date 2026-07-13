import UIKit

class DateHeadingView: UIView {
    private var titleLabel: UILabel?

    var title = "" {
        didSet {
            titleLabel?.text = title
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        setup()
    }

    private func setup() {
        let label = UILabel()

        label.textAlignment = .natural
        label.text = title
        label.font = UIFont.font(ofSize: 22, weight: UIFont.Weight.bold, scalingWith: .largeTitle)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        titleLabel = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.topAnchor.constraint(equalTo: topAnchor)
        ])

        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.setBgColorForTheme()
        }
        setBgColorForTheme()
    }

    private var themeToken: NotificationCenter.ObservationToken?

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setBgColorForTheme() {
        backgroundColor = .clear
    }
}
