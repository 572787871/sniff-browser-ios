import UIKit

enum AppAppearance {
    static let quickAnimationDuration: TimeInterval = 0.18
    static let standardAnimationDuration: TimeInterval = 0.28
    private static var transparencyObserver: NSObjectProtocol?

    /// 在 App 启动时调用一次，统一系统导航组件的基础外观。
    static func configure() {
        applyNavigationAppearance()
        guard transparencyObserver == nil else { return }
        transparencyObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppAppearance.applyNavigationAppearance()
        }
    }

    private static func applyNavigationAppearance() {
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithDefaultBackground()
        navigationAppearance.backgroundEffect = UIAccessibility.isReduceTransparencyEnabled
            ? nil
            : UIBlurEffect(style: .systemChromeMaterial)
        navigationAppearance.backgroundColor = UIAccessibility.isReduceTransparencyEnabled
            ? AppColors.chromeFallback
            : AppColors.elevatedSurface
        navigationAppearance.shadowColor = AppColors.separator
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: AppColors.primaryText,
            .font: AppTypography.headline
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: AppColors.primaryText,
            .font: AppTypography.largeTitle
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = navigationAppearance
        navigationBar.compactAppearance = navigationAppearance
        navigationBar.scrollEdgeAppearance = navigationAppearance
        navigationBar.tintColor = AppColors.accent

        UIBarButtonItem.appearance().tintColor = AppColors.accent
        UIRefreshControl.appearance().tintColor = AppColors.secondaryText
    }

    /// 统一处理 Reduce Motion。减少动态效果时使用短淡入淡出，不产生位移或弹性。
    static func animate(
        duration: TimeInterval = standardAnimationDuration,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: quickAnimationDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: animations,
                completion: completion
            )
            return
        }

        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }
}

/// 会随“降低透明度”设置实时切换的原生材质容器。
final class AppMaterialView: UIVisualEffectView {
    private let preferredStyle: UIBlurEffect.Style
    private let fallbackColor: UIColor
    private var transparencyObserver: NSObjectProtocol?

    init(
        style: UIBlurEffect.Style = .systemMaterial,
        fallbackColor: UIColor = AppColors.chromeFallback
    ) {
        preferredStyle = style
        self.fallbackColor = fallbackColor
        super.init(effect: nil)
        updateMaterial()
        observeTransparencyChanges()
    }

    required init?(coder: NSCoder) {
        preferredStyle = .systemMaterial
        fallbackColor = AppColors.chromeFallback
        super.init(coder: coder)
        updateMaterial()
        observeTransparencyChanges()
    }

    deinit {
        if let transparencyObserver {
            NotificationCenter.default.removeObserver(transparencyObserver)
        }
    }

    private func updateMaterial() {
        if UIAccessibility.isReduceTransparencyEnabled {
            effect = nil
            backgroundColor = fallbackColor
        } else {
            backgroundColor = .clear
            effect = UIBlurEffect(style: preferredStyle)
        }
    }

    private func observeTransparencyChanges() {
        transparencyObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMaterial()
        }
    }
}
