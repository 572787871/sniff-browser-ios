import UIKit

enum AppAppearance {
    static let quickAnimationDuration: TimeInterval = 0.18
    static let standardAnimationDuration: TimeInterval = 0.28
    private static var transparencyObserver: NSObjectProtocol?

    /// 在 App 启动时调用一次，统一系统导航组件的基础外观。
    static func configure() {
        applyNavigationAppearance()
        applyControlAppearance()
        guard transparencyObserver == nil else { return }
        transparencyObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppAppearance.applyNavigationAppearance()
        }
    }

    /// 主题色 trait 变化时更新系统外观代理；现有视图由动态色自动重绘。
    static func refreshThemeAppearance() {
        applyNavigationAppearance()
        applyControlAppearance()
    }

    private static func applyNavigationAppearance() {
        let standardAppearance = UINavigationBarAppearance()
        if UIAccessibility.isReduceTransparencyEnabled {
            standardAppearance.configureWithOpaqueBackground()
            standardAppearance.backgroundColor = AppColors.background
        } else {
            standardAppearance.configureWithDefaultBackground()
        }
        standardAppearance.titleTextAttributes = [
            .foregroundColor: AppColors.primaryText,
            .font: AppTypography.headline
        ]
        standardAppearance.largeTitleTextAttributes = [
            .foregroundColor: AppColors.primaryText,
            .font: AppTypography.largeTitle
        ]

        let scrollEdgeAppearance = UINavigationBarAppearance()
        if UIAccessibility.isReduceTransparencyEnabled {
            scrollEdgeAppearance.configureWithOpaqueBackground()
            scrollEdgeAppearance.backgroundColor = AppColors.background
        } else {
            scrollEdgeAppearance.configureWithTransparentBackground()
        }
        scrollEdgeAppearance.shadowColor = .clear
        scrollEdgeAppearance.titleTextAttributes = standardAppearance.titleTextAttributes
        scrollEdgeAppearance.largeTitleTextAttributes = standardAppearance.largeTitleTextAttributes

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = standardAppearance
        navigationBar.compactAppearance = standardAppearance
        navigationBar.scrollEdgeAppearance = scrollEdgeAppearance
        navigationBar.tintColor = AppColors.accent

        UIBarButtonItem.appearance().tintColor = AppColors.accent
        UIRefreshControl.appearance().tintColor = AppColors.secondaryText
    }

    private static func applyControlAppearance() {
        UISwitch.appearance().onTintColor = AppColors.accent
        // Keep the native segmented-control surface and use the global accent
        // only for the selected label. This avoids a translucent colored slab
        // while still making the user's theme choice visible.
        UISegmentedControl.appearance().selectedSegmentTintColor = AppColors.surface
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: AppColors.secondaryText],
            for: .normal
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: AppColors.accent],
            for: .selected
        )
        UISearchBar.appearance().tintColor = AppColors.accent
        UITextField.appearance().tintColor = AppColors.accent
        UIProgressView.appearance().progressTintColor = AppColors.accent
        UIProgressView.appearance().trackTintColor = AppColors.progressTrack
        UIPageControl.appearance().currentPageIndicatorTintColor = AppColors.accent
        UIPageControl.appearance().pageIndicatorTintColor = AppColors.tertiarySurface
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

/// 品牌图形集中在代码中生成，避免把页面图标锁死在单一分辨率位图里。
@MainActor
enum AppIconography {
    static func scanApertureImage(
        pointSize: CGFloat,
        weight: CGFloat = 2.2
    ) -> UIImage {
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.setLineWidth(weight)
            cgContext.setLineCap(.round)

            let center = CGPoint(x: pointSize * 0.43, y: pointSize * 0.5)
            for radius in [pointSize * 0.17, pointSize * 0.29, pointSize * 0.41] {
                cgContext.addArc(
                    center: center,
                    radius: radius,
                    startAngle: -0.58 * CGFloat.pi,
                    endAngle: 0.58 * CGFloat.pi,
                    clockwise: false
                )
                cgContext.strokePath()
            }

            let dotRadius = max(1.6, pointSize * 0.075)
            let dotCenter = CGPoint(x: pointSize * 0.44, y: pointSize * 0.5)
            cgContext.fillEllipse(in: CGRect(
                x: dotCenter.x - dotRadius,
                y: dotCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// 应用图标的镂空版本：去掉炭黑方块底，只保留内部的扫描弧线与双信号点，
    /// 作为工具栏线条图标使用（模板色跟随 tintColor）。
    static func appIconMarkImage(
        pointSize: CGFloat,
        fillRatio: CGFloat = 0.88
    ) -> UIImage {
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        // 原始图形外接框（按 1024 画布坐标）：x ∈ [248, 774]，y ∈ [194, 756]。
        let markSize: CGFloat = 562
        let markCenterX: CGFloat = 511
        let markCenterY: CGFloat = 475
        let scale = pointSize * fillRatio / markSize
        let translateX = pointSize / 2 - markCenterX * scale
        let translateY = pointSize / 2 - markCenterY * scale
        let image = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.saveGState()
            cgContext.concatenate(CGAffineTransform(
                a: scale,
                b: 0,
                c: 0,
                d: scale,
                tx: translateX,
                ty: translateY
            ))

            let arcs = UIBezierPath()
            arcs.lineWidth = 58
            arcs.lineCapStyle = .round
            arcs.move(to: CGPoint(x: 248, y: 720))
            arcs.addCurve(
                to: CGPoint(x: 720, y: 248),
                controlPoint1: CGPoint(x: 248, y: 459),
                controlPoint2: CGPoint(x: 459, y: 248)
            )
            arcs.move(to: CGPoint(x: 360, y: 720))
            arcs.addCurve(
                to: CGPoint(x: 720, y: 360),
                controlPoint1: CGPoint(x: 360, y: 521),
                controlPoint2: CGPoint(x: 521, y: 360)
            )
            arcs.move(to: CGPoint(x: 472, y: 720))
            arcs.addCurve(
                to: CGPoint(x: 720, y: 472),
                controlPoint1: CGPoint(x: 472, y: 583),
                controlPoint2: CGPoint(x: 583, y: 472)
            )
            arcs.stroke()

            UIBezierPath(
                ovalIn: CGRect(
                    x: 720 - 54,
                    y: 248 - 54,
                    width: 108,
                    height: 108
                )
            ).fill()
            UIBezierPath(
                ovalIn: CGRect(
                    x: 720 - 36,
                    y: 720 - 36,
                    width: 72,
                    height: 72
                )
            ).fill()
            cgContext.restoreGState()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    static func tabStackImage(
        pointSize: CGFloat,
        weight: CGFloat = 1.8
    ) -> UIImage {
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setLineWidth(weight)
            cgContext.setLineJoin(.round)

            let side = pointSize * 0.58
            let offset = pointSize * 0.20
            let inset = max(weight, pointSize * 0.08)
            let radius = pointSize * 0.13
            let rearRect = CGRect(
                x: inset + offset,
                y: inset,
                width: side,
                height: side
            )
            let frontRect = CGRect(
                x: inset,
                y: inset + offset,
                width: side,
                height: side
            )
            cgContext.addPath(
                UIBezierPath(roundedRect: rearRect, cornerRadius: radius).cgPath
            )
            cgContext.strokePath()
            cgContext.addPath(
                UIBezierPath(roundedRect: frontRect, cornerRadius: radius).cgPath
            )
            cgContext.strokePath()
        }
        return image.withRenderingMode(.alwaysTemplate)
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
