import Foundation
import UIKit
import PocketCastsUtils

class TranscriptErrorView: UIView {
    enum ViewSource {
        case player
        case episode
    }

    private var retryCallback: (() -> ())?
    private let viewSource: ViewSource

    init(source: ViewSource = .player, retryCallback: (() -> ())?) {
        self.viewSource = source
        self.retryCallback = retryCallback
        super.init(frame: CGRect.zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        NSLayoutConstraint.activate(
            [
                containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
                containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
                containerView.widthAnchor.constraint(equalTo: widthAnchor),
                containerView.heightAnchor.constraint(equalTo: heightAnchor)
            ]
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var containerView: UIView = {
        let view = UIStackView(arrangedSubviews: [icon, label, retryButton, generateButton])
        view.spacing = 16
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.distribution = .equalCentering
        view.alignment = .center
        return view
    }()

    private lazy var icon: UIImageView = {
        let view = UIImageView(image: UIImage(named: "yield_scaled")?.withRenderingMode(.alwaysTemplate))
        view.tintColor = viewSource == .episode ? ThemeColor.primaryIcon02() : .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var retryButton: UIView = {
        var configuration = UIButton.Configuration.filled()
        configuration.contentInsets = .init(top: 4, leading: 12, bottom: 4, trailing: 12)

        let retryButton = RoundButton(type: .system)
        retryButton.setTitle(L10n.tryAgain, for: .normal)
        retryButton.addTarget(self, action: #selector(retryLoad), for: .touchUpInside)

        if viewSource == .episode {
            retryButton.setTitleColor(ThemeColor.primaryText01(), for: .normal)
            retryButton.tintColor = ThemeColor.primaryUi05()
        } else {
            retryButton.setTitleColor(.white, for: .normal)
            retryButton.tintColor = .white.withAlphaComponent(0.2)
        }
        retryButton.layer.masksToBounds = true
        retryButton.configuration = configuration
        retryButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .callout)
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        return retryButton
    }()

    private lazy var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        return label
    }()

    func setMessage(_ message: String, attributes: [NSAttributedString.Key: Any]) {
        var updatedAttributes = attributes
        if viewSource == .episode {
            updatedAttributes[.foregroundColor] = ThemeColor.primaryText01()
        }
        label.attributedText = NSAttributedString(string: message, attributes: updatedAttributes)
    }

    func setTextAttributes(_ attributes: [NSAttributedString.Key: Any]) {
        if let text = label.text {
            var updatedAttributes = attributes
            if viewSource == .episode {
                updatedAttributes[.foregroundColor] = ThemeColor.primaryText01()
            }
            label.attributedText = NSAttributedString(string: text, attributes: updatedAttributes)
        }
    }

    /// Secondary affordance under the retry button, used to offer generating an
    /// on-device transcript when none is available. Hidden until shown.
    private var generateCallback: (() -> Void)?

    private lazy var generateButton: UIView = {
        var configuration = UIButton.Configuration.filled()
        configuration.contentInsets = .init(top: 4, leading: 12, bottom: 4, trailing: 12)

        let generateButton = RoundButton(type: .system)
        generateButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)

        if viewSource == .episode {
            generateButton.setTitleColor(ThemeColor.primaryText01(), for: .normal)
            generateButton.tintColor = ThemeColor.primaryUi05()
        } else {
            generateButton.setTitleColor(.white, for: .normal)
            generateButton.tintColor = .white.withAlphaComponent(0.2)
        }
        generateButton.layer.masksToBounds = true
        generateButton.configuration = configuration
        generateButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .callout)
        generateButton.titleLabel?.adjustsFontForContentSizeCategory = true
        generateButton.isHidden = true
        return generateButton
    }()

    func showGenerateButton(title: String, action: @escaping () -> Void) {
        generateCallback = action
        (generateButton as? UIButton)?.setTitle(title, for: .normal)
        generateButton.isHidden = false
    }

    func hideGenerateButton() {
        generateButton.isHidden = true
    }

    func setRetryButtonHidden(_ hidden: Bool) {
        retryButton.isHidden = hidden
    }

    @objc private func generateTapped() {
        generateCallback?()
    }

    @objc func retryLoad() {
        retryCallback?()
    }

    override var intrinsicContentSize: CGSize {
        return containerView.intrinsicContentSize
    }
}
