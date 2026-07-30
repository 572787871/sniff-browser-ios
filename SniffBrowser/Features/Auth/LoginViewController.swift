import UIKit

final class LoginViewController: BaseViewController {
    var onAuthenticated: ((AuthSession) -> Void)?

    private let provider: AuthProviding?
    private var authenticationTask: Task<Void, Never>?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let iconView = UIImageView(image: UIImage(systemName: "person.crop.circle.badge.checkmark"))
    private let headingLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let modeControl = UISegmentedControl(items: ["登录", "注册"])
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let statusLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private let forgotPasswordButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init(provider: AuthProviding? = nil) {
        self.provider = provider
        super.init(title: "账户", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        updateMode()
    }

    private func configureView() {
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        iconView.tintColor = AppColors.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48)
        iconView.contentMode = .center
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        headingLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        headingLabel.adjustsFontForContentSizeCategory = true
        headingLabel.textAlignment = .center
        headingLabel.numberOfLines = 0

        descriptionLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.textColor = AppColors.secondaryText
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0

        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        configureTextField(
            emailField,
            placeholder: "邮箱",
            contentType: .emailAddress,
            keyboardType: .emailAddress
        )
        emailField.autocapitalizationType = .none

        configureTextField(
            passwordField,
            placeholder: "密码",
            contentType: .password,
            keyboardType: .default
        )
        passwordField.isSecureTextEntry = true
        passwordField.returnKeyType = .done
        passwordField.addTarget(self, action: #selector(submitPressed), for: .editingDidEndOnExit)

        statusLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = AppColors.secondaryText
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        var submitConfiguration = UIButton.Configuration.filled()
        submitConfiguration.cornerStyle = .medium
        submitButton.configuration = submitConfiguration
        submitButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        submitButton.addTarget(self, action: #selector(submitPressed), for: .touchUpInside)
        submitButton.heightAnchor.constraint(
            greaterThanOrEqualToConstant: AppMetrics.primaryButtonHeight
        ).isActive = true

        forgotPasswordButton.setTitle("忘记密码", for: .normal)
        forgotPasswordButton.addTarget(
            self,
            action: #selector(forgotPasswordPressed),
            for: .touchUpInside
        )
        forgotPasswordButton.heightAnchor.constraint(
            greaterThanOrEqualToConstant: AppMetrics.minimumTapSize
        ).isActive = true

        loadingIndicator.hidesWhenStopped = true

        [
            iconView,
            headingLabel,
            descriptionLabel,
            modeControl,
            emailField,
            passwordField,
            statusLabel,
            submitButton,
            loadingIndicator,
            forgotPasswordButton
        ].forEach(contentStack.addArrangedSubview)

        contentStack.setCustomSpacing(24, after: descriptionLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 32),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),

            emailField.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            passwordField.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            authenticationTask?.cancel()
        }
    }

    private func configureTextField(
        _ field: UITextField,
        placeholder: String,
        contentType: UITextContentType,
        keyboardType: UIKeyboardType
    ) {
        field.placeholder = placeholder
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textContentType = contentType
        field.keyboardType = keyboardType
        field.backgroundColor = AppColors.surface
        field.layer.cornerRadius = AppRadius.input
        field.layer.cornerCurve = .continuous
        field.clearButtonMode = .whileEditing
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.rightViewMode = .always
        field.accessibilityLabel = placeholder
    }

    private func updateMode() {
        let isRegistration = modeControl.selectedSegmentIndex == 1
        headingLabel.text = isRegistration ? "创建账户" : "欢迎回来"
        descriptionLabel.text = isRegistration
            ? "使用邮箱创建账户。配置认证服务后，将向邮箱发送验证信息。"
            : "登录后可在未来版本中同步收藏、历史记录和下载记录。"
        submitButton.configuration?.title = isRegistration ? "注册" : "登录"
        forgotPasswordButton.isHidden = isRegistration
        statusLabel.text = provider == nil
            ? "当前未配置 Supabase，浏览器将继续以游客模式正常使用。"
            : nil
        statusLabel.textColor = AppColors.secondaryText
    }

    private func credentials() -> (email: String, password: String)? {
        let email = emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        guard email.contains("@"), !password.isEmpty else {
            showStatus("请输入有效邮箱和密码。", isError: true)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return nil
        }
        return (email, password)
    }

    private func authenticate() {
        guard let provider else {
            showStatus("登录服务尚未配置，当前可继续使用游客模式。", isError: false)
            return
        }
        guard let credentials = credentials() else { return }

        setLoading(true)
        let isRegistration = modeControl.selectedSegmentIndex == 1
        authenticationTask?.cancel()
        authenticationTask = Task { [weak self] in
            do {
                let session = if isRegistration {
                    try await provider.signUp(
                        email: credentials.email,
                        password: credentials.password
                    )
                } else {
                    try await provider.signIn(
                        email: credentials.email,
                        password: credentials.password
                    )
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.setLoading(false)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self?.onAuthenticated?(session)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.setLoading(false)
                    self?.showStatus("登录未完成，请检查网络或账户信息后重试。", isError: true)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func setLoading(_ isLoading: Bool) {
        submitButton.isEnabled = !isLoading
        modeControl.isEnabled = !isLoading
        emailField.isEnabled = !isLoading
        passwordField.isEnabled = !isLoading
        isLoading ? loadingIndicator.startAnimating() : loadingIndicator.stopAnimating()
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.text = message
        statusLabel.textColor = isError ? AppColors.danger : AppColors.secondaryText
    }

    @objc private func modeChanged() {
        updateMode()
    }

    @objc private func submitPressed() {
        view.endEditing(true)
        authenticate()
    }

    @objc private func forgotPasswordPressed() {
        guard let provider else {
            showStatus("密码重置服务尚未配置。", isError: false)
            return
        }
        let email = emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard email.contains("@") else {
            showStatus("请先输入用于重置密码的邮箱。", isError: true)
            return
        }

        setLoading(true)
        authenticationTask?.cancel()
        authenticationTask = Task { [weak self] in
            do {
                try await provider.requestPasswordReset(email: email)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.setLoading(false)
                    self?.showStatus("重置邮件已发送，请检查邮箱。", isError: false)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.setLoading(false)
                    self?.showStatus("暂时无法发送重置邮件，请稍后重试。", isError: true)
                }
            }
        }
    }
}
