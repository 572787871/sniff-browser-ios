import UIKit

struct AddressBarState: Equatable {
  var url: URL?
  var isLoading = false
  var progress = 0.0
  var isEditing = false
}

@MainActor
protocol AddressBarDelegate: AnyObject {
  func addressBar(_ addressBar: AddressBarView, didSubmit text: String)
  func addressBar(_ addressBar: AddressBarView, didChangeText text: String)
  func addressBarDidRequestReload(_ addressBar: AddressBarView)
  func addressBarDidRequestStop(_ addressBar: AddressBarView)
  func addressBarDidRequestDismissSearch(_ addressBar: AddressBarView)
  func addressBarDidBeginEditing(_ addressBar: AddressBarView)
  func addressBarDidEndEditing(_ addressBar: AddressBarView)
}

final class AddressBarView: UIView {
  weak var delegate: AddressBarDelegate?

  private let materialView = AppMaterialView(
    style: .systemUltraThinMaterial,
    fallbackColor: AppColors.chromeFallback
  )
  private let securityImageView = UIImageView()
  private let textField = UITextField()
  private let trailingButton = UIButton(type: .system)
  private let progressView = UIProgressView(progressViewStyle: .bar)
  private var state = AddressBarState()
  private var isCompact = false
  private var pageThemeColor: UIColor?
  private var pageThemeForegroundStyle: BrowserChromeForegroundStyle?
  private var isPrivateMode = false

  var isEditing: Bool {
    textField.isFirstResponder
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateResolvedColors()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.shadowPath = UIBezierPath(
      roundedRect: bounds,
      cornerRadius: AppRadius.input
    ).cgPath
  }

  func apply(_ state: AddressBarState) {
    self.state = state
    if !textField.isFirstResponder {
      textField.text = displayText(for: state.url)
      textField.textAlignment = isCompact
        ? .center
        : (state.url == nil ? .center : .left)
    }
    updateSecurityIcon(for: state.url)
    updateTrailingButton()
    progressView.setProgress(
      Float(state.progress),
      animated: !UIAccessibility.isReduceMotionEnabled
    )
    progressView.isHidden = !state.isLoading || state.progress >= 1
    progressView.accessibilityElementsHidden = progressView.isHidden
    progressView.accessibilityValue = "\(Int((state.progress * 100).rounded()))%"
  }

  func beginEditing() {
    setCompact(false, animated: false)
    textField.becomeFirstResponder()
  }

  func setInput(_ input: String) {
    textField.text = input
    updateTrailingButton()
  }

  func submitInput() {
    delegate?.addressBar(self, didSubmit: textField.text ?? "")
    textField.resignFirstResponder()
  }

  func applyPageTheme(
    _ theme: WebPageThemeColor?,
    foregroundStyle: BrowserChromeForegroundStyle?
  ) {
    pageThemeColor = theme?.uiColor
    pageThemeForegroundStyle = foregroundStyle
    updateResolvedColors()
    updateSecurityIcon(for: state.url)
  }

  func setPrivateMode(_ isPrivate: Bool) {
    guard isPrivateMode != isPrivate else { return }
    isPrivateMode = isPrivate
    overrideUserInterfaceStyle = isPrivate ? .dark : .unspecified
    updateResolvedColors()
    updateSecurityIcon(for: state.url)
  }

  func setCompact(_ compact: Bool, animated: Bool) {
    guard compact != isCompact else { return }
    if compact, textField.isFirstResponder {
      return
    }
    isCompact = compact
    let changes = {
      self.materialView.transform = compact
        && !UIAccessibility.isReduceMotionEnabled
        ? CGAffineTransform(scaleX: 0.74, y: 0.80)
        : .identity
      self.securityImageView.alpha = compact ? 0 : 1
      self.trailingButton.alpha = compact ? 0 : 1
      self.textField.textAlignment = compact ? .center : (
        self.state.url == nil ? .center : .left
      )
      self.layer.shadowOpacity = compact ? 0.04 : AppShadow.browserChrome.opacity
    }
    // 收缩时图标只作为视觉元素隐藏；地址栏本身仍要保留可触摸区域，
    // 点击收缩后的地址栏可以恢复编辑状态。
    securityImageView.isUserInteractionEnabled = true
    trailingButton.isUserInteractionEnabled = true
    guard animated else {
      changes()
      return
    }
    AppAppearance.animate(duration: 0.24, animations: changes)
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 0,
      leading: AppSpacing.sm,
      bottom: 0,
      trailing: AppSpacing.xs
    )

    materialView.translatesAutoresizingMaskIntoConstraints = false
    materialView.layer.cornerRadius = AppRadius.input
    materialView.layer.cornerCurve = .continuous
    materialView.clipsToBounds = true
    materialView.layer.borderWidth = 0.75
    addSubview(materialView)
    AppShadow.browserChrome.apply(to: self)

    let editingGesture = UITapGestureRecognizer(
      target: self,
      action: #selector(addressBarTapped)
    )
    editingGesture.cancelsTouchesInView = false
    editingGesture.delegate = self
    addGestureRecognizer(editingGesture)

    securityImageView.translatesAutoresizingMaskIntoConstraints = false
    securityImageView.tintColor = AppColors.secondaryText
    securityImageView.contentMode = .scaleAspectFit
    securityImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: 14,
      weight: .regular
    )
    securityImageView.isAccessibilityElement = true
    securityImageView.accessibilityTraits = .image
    materialView.contentView.addSubview(securityImageView)



    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.delegate = self
    textField.font = AppTypography.body
    textField.adjustsFontForContentSizeCategory = true
    textField.textColor = AppColors.primaryText
    textField.tintColor = AppColors.accent
    textField.placeholder = "搜索或输入网址"
    textField.autocapitalizationType = .none
    textField.autocorrectionType = .no
    textField.spellCheckingType = .no
    textField.keyboardType = .URL
    textField.returnKeyType = .go
    textField.clearButtonMode = .never
    textField.accessibilityLabel = "地址与搜索"
    textField.accessibilityIdentifier = "browser.address"
    textField.addTarget(
      self,
      action: #selector(textDidChange),
      for: .editingChanged
    )
    materialView.contentView.addSubview(textField)

    trailingButton.translatesAutoresizingMaskIntoConstraints = false
    trailingButton.tintColor = AppColors.secondaryText
    trailingButton.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 19, weight: .regular),
      forImageIn: .normal
    )
    trailingButton.accessibilityIdentifier = "browser.reloadOrStop"
    trailingButton.addTarget(
      self,
      action: #selector(trailingButtonPressed),
      for: .touchUpInside
    )
    materialView.contentView.addSubview(trailingButton)

    progressView.translatesAutoresizingMaskIntoConstraints = false
    progressView.progressTintColor = AppColors.accent
    progressView.trackTintColor = .clear
    progressView.isHidden = true
    progressView.isAccessibilityElement = true
    progressView.accessibilityLabel = "网页载入进度"
    materialView.contentView.addSubview(progressView)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: AppMetrics.addressBarHeight),
      materialView.topAnchor.constraint(equalTo: topAnchor),
      materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
      materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
      materialView.bottomAnchor.constraint(equalTo: bottomAnchor),

      securityImageView.leadingAnchor.constraint(
        equalTo: materialView.contentView.leadingAnchor,
        constant: AppSpacing.sm
      ),
      securityImageView.centerYAnchor.constraint(
        equalTo: materialView.contentView.centerYAnchor
      ),
      securityImageView.widthAnchor.constraint(equalToConstant: 18),
      securityImageView.heightAnchor.constraint(equalToConstant: 18),

      textField.leadingAnchor.constraint(
        equalTo: securityImageView.trailingAnchor,
        constant: AppSpacing.xs
      ),
      textField.trailingAnchor.constraint(
        equalTo: trailingButton.leadingAnchor,
        constant: -AppSpacing.xs
      ),
      textField.topAnchor.constraint(equalTo: materialView.contentView.topAnchor),
      textField.bottomAnchor.constraint(equalTo: materialView.contentView.bottomAnchor),

      trailingButton.trailingAnchor.constraint(
        equalTo: materialView.contentView.trailingAnchor,
        constant: -AppSpacing.xs
      ),
      trailingButton.centerYAnchor.constraint(
        equalTo: materialView.contentView.centerYAnchor
      ),
      trailingButton.widthAnchor.constraint(
        equalToConstant: AppMetrics.minimumTapSize
      ),
      trailingButton.heightAnchor.constraint(
        equalToConstant: AppMetrics.minimumTapSize
      ),

      progressView.leadingAnchor.constraint(
        equalTo: materialView.contentView.leadingAnchor,
        constant: AppRadius.input
      ),
      progressView.trailingAnchor.constraint(
        equalTo: materialView.contentView.trailingAnchor,
        constant: -AppRadius.input
      ),
      progressView.bottomAnchor.constraint(
        equalTo: materialView.contentView.bottomAnchor
      ),
      progressView.heightAnchor.constraint(equalToConstant: 2),
    ])
    updateResolvedColors()
    registerForTraitChanges([
      UITraitUserInterfaceStyle.self,
      UITraitAccessibilityContrast.self,
    ]) { (view: AddressBarView, _) in
      view.updateResolvedColors()
    }
    updateSecurityIcon(for: nil)
    updateTrailingButton()
  }

  private func updateResolvedColors() {
    let foreground = isPrivateMode
      ? UIColor.white
      : pageThemeForegroundStyle?.color
    let borderColor = foreground?.withAlphaComponent(
      UIAccessibility.isDarkerSystemColorsEnabled ? 0.28 : 0.16
    ) ?? AppColors.browserChromeBorder.resolvedColor(with: traitCollection)
    materialView.layer.borderColor = borderColor.cgColor
    if isPrivateMode {
      materialView.contentView.backgroundColor =
        AppColors.privateBrowsingSurface.withAlphaComponent(0.74)
    } else {
      materialView.contentView.backgroundColor = pageThemeColor?
        .withAlphaComponent(
          pageThemeForegroundStyle == .light ? 0.28 : 0.16
        ) ?? AppColors.browserChromeTint
    }
    textField.textColor = foreground ?? AppColors.primaryText
    textField.tintColor = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : (foreground ?? AppColors.accent)
    trailingButton.tintColor = foreground ?? AppColors.secondaryText
    progressView.progressTintColor = isPrivateMode
      ? AppColors.privateBrowsingAccent
      : (foreground ?? AppColors.accent)
    if let foreground {
      textField.attributedPlaceholder = NSAttributedString(
        string: "搜索或输入网址",
        attributes: [.foregroundColor: foreground.withAlphaComponent(0.58)]
      )
    } else {
      textField.attributedPlaceholder = nil
      textField.placeholder = "搜索或输入网址"
    }
    layer.shadowColor = UIColor.black.cgColor
  }

  private func displayText(for url: URL?) -> String? {
    guard let url else { return nil }
    return url.host ?? url.absoluteString
  }

  private func updateSecurityIcon(for url: URL?) {
    let symbol: String
    let color: UIColor
    if textField.isFirstResponder, !isPrivateMode {
      symbol = "globe"
      color = pageThemeForegroundStyle?.color ?? AppColors.accent
      securityImageView.accessibilityLabel = "正在编辑地址与搜索"
    } else if isPrivateMode {
      symbol = "eye.slash.fill"
      color = AppColors.privateBrowsingAccent
      securityImageView.accessibilityLabel = "无痕浏览模式"
    } else {
      switch url?.scheme?.lowercased() {
      case "https":
        symbol = "lock.fill"
        color = pageThemeForegroundStyle?.color ?? AppColors.secondaryText
        securityImageView.accessibilityLabel = "安全连接"
      case "http":
        symbol = "exclamationmark.triangle.fill"
        color = AppColors.warning
        securityImageView.accessibilityLabel = "连接不安全"
      default:
        symbol = "globe"
        color = pageThemeForegroundStyle?.color ?? AppColors.secondaryText
        securityImageView.accessibilityLabel = "新标签页"
      }
    }
    securityImageView.image = UIImage(systemName: symbol)
    securityImageView.tintColor = color
    textField.accessibilityHint = securityImageView.accessibilityLabel
  }

  private func updateTrailingButton() {
    let isEditing = textField.isFirstResponder
    let isEditingWithText = textField.isFirstResponder
      && textField.text?.isEmpty == false
    let symbol = isEditingWithText
      ? "xmark"
      : (isEditing ? "xmark" : (state.isLoading ? "xmark" : "arrow.clockwise"))
    trailingButton.setImage(UIImage(systemName: symbol), for: .normal)
    trailingButton.accessibilityLabel = isEditingWithText
      ? "清除"
      : (isEditing ? "关闭搜索" : (state.isLoading ? "停止载入" : "重新载入"))
  }

  @objc private func textDidChange() {
    updateTrailingButton()
    delegate?.addressBar(
      self,
      didChangeText: textField.text ?? ""
    )
  }

  @objc private func trailingButtonPressed() {
    if textField.isFirstResponder, textField.text?.isEmpty == false {
      textField.text = ""
      updateTrailingButton()
      delegate?.addressBar(self, didChangeText: "")
      return
    }
    if textField.isFirstResponder {
      delegate?.addressBarDidRequestDismissSearch(self)
      textField.resignFirstResponder()
      return
    }
    state.isLoading
      ? delegate?.addressBarDidRequestStop(self)
      : delegate?.addressBarDidRequestReload(self)
  }

  @objc private func addressBarTapped() {
    guard !textField.isFirstResponder else { return }
    beginEditing()
  }
}

extension AddressBarView: UITextFieldDelegate, UIGestureRecognizerDelegate {
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    var candidate: UIView? = touch.view
    while let view = candidate, view !== self {
      if view is UIControl {
        return false
      }
      candidate = view.superview
    }
    return true
  }

  func textFieldDidBeginEditing(_ textField: UITextField) {
    setCompact(false, animated: false)
    state.isEditing = true
    textField.text = state.url?.absoluteString
    textField.textAlignment = .left
    updateSecurityIcon(for: state.url)
    updateTrailingButton()
    DispatchQueue.main.async { textField.selectAll(nil) }
    delegate?.addressBarDidBeginEditing(self)
  }

  func textFieldDidEndEditing(_ textField: UITextField) {
    state.isEditing = false
    textField.text = displayText(for: state.url)
    textField.textAlignment = state.url == nil ? .center : .left
    updateSecurityIcon(for: state.url)
    updateTrailingButton()
    delegate?.addressBarDidEndEditing(self)
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    submitInput()
    return true
  }
}
