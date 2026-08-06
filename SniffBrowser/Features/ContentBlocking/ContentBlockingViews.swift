import UIKit

// MARK: - 区块标题（蓝色竖杠 + 标题 + 可选右侧控件）

/// 内容拦截页的区块标题：左侧蓝色小竖杠 + 加粗标题，右侧可挂筛选按钮。
final class ContentBlockSectionHeaderView: UIView {
    private let barView = UIView()
    private let titleLabel = UILabel()

    init(title: String, trailing: UIView? = nil) {
        super.init(frame: .zero)

        barView.backgroundColor = AppColors.accent
        barView.layer.cornerRadius = 2
        barView.layer.cornerCurve = .continuous
        barView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barView)

        AppTypography.configure(titleLabel, style: .headline, weight: .semibold)
        titleLabel.text = title
        titleLabel.textColor = AppColors.primaryText
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            barView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            barView.centerYAnchor.constraint(equalTo: centerYAnchor),
            barView.widthAnchor.constraint(equalToConstant: 3.5),
            barView.heightAnchor.constraint(equalToConstant: 15),
            titleLabel.leadingAnchor.constraint(equalTo: barView.trailingAnchor, constant: 7),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -16
            )
        ])

        if let trailing {
            trailing.translatesAutoresizingMaskIntoConstraints = false
            addSubview(trailing)
            NSLayoutConstraint.activate([
                trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                trailing.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

// MARK: - 卡片阴影

enum ContentBlockCardStyle {
    static func applyShadow(to view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.07
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 3)
        view.layer.shadowPath = nil
    }
}

// MARK: - 总开关卡片

/// 顶部内容拦截总开关：白色圆角卡片 + 3D 盾牌图标（生成素材）+ UISwitch。
final class ContentBlockMasterCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockMasterCardCell"

    private let cardView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggle = UISwitch()
    private var onChange: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        title: String,
        subtitle: String,
        isOn: Bool,
        accessibilityIdentifier: String,
        onChange: @escaping (Bool) -> Void
    ) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        toggle.setOn(isOn, animated: false)
        self.onChange = onChange
        self.accessibilityIdentifier = accessibilityIdentifier
        toggle.accessibilityIdentifier = "\(accessibilityIdentifier).switch"
        accessibilityLabel = "\(title)，\(subtitle)"
        accessibilityValue = isOn ? "已开启" : "已关闭"
        toggle.accessibilityLabel = title
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onChange = nil
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        accessibilityValue = nil
    }

    @objc private func toggleChanged() {
        accessibilityValue = toggle.isOn ? "已开启" : "已关闭"
        onChange?(toggle.isOn)
    }

    private func configureView() {
        backgroundColor = .clear
        backgroundConfiguration = UIBackgroundConfiguration.clear()
        selectionStyle = .none

        cardView.backgroundColor = AppColors.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        ContentBlockCardStyle.applyShadow(to: cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        if let shield = UIImage(named: "ContentBlockShield") {
            iconView.image = shield
            iconView.contentMode = .scaleAspectFit
        } else {
            // 素材缺失时的兜底：系统蓝色盾牌闪电图标。
            iconView.image = UIImage(
                systemName: "bolt.shield.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 24,
                    weight: .semibold
                )
            )
            iconView.tintColor = AppColors.accent
            iconView.contentMode = .center
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(iconView)

        AppTypography.configure(titleLabel, style: .body, weight: .semibold)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        AppTypography.configure(subtitleLabel, style: .footnote)
        subtitleLabel.textColor = AppColors.secondaryText
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(subtitleLabel)

        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(toggle)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 15),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -14),

            toggle.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        ])
    }
}

// MARK: - 拦截统计 2×2 卡片

/// 拦截统计：四张独立白色圆角卡片，每张含彩色图标、大数字、标题与底部趋势图。
final class ContentBlockStatsCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockStatsCardCell"

    private let gridStack = UIStackView()
    private var tiles: [StatTileView] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        blocked: Int,
        pageLoads: Int,
        ruleCount: Int,
        filterCount: Int,
        blockedTitle: String,
        pageLoadTitle: String,
        blockedSeries: [Double],
        pageLoadSeries: [Double],
        ruleSeries: [Double],
        filterSeries: [Double]
    ) {
        let updates: [(Int, StatTileView)] = [
            (0, tiles[0]), (1, tiles[1]),
            (2, tiles[2]), (3, tiles[3])
        ]
        let values: [(symbol: String, title: String, value: Int, color: UIColor, series: [Double])] = [
            ("shield.fill", blockedTitle, blocked, .systemRed, blockedSeries),
            ("globe.asia.australia.fill", pageLoadTitle, pageLoads, .systemBlue, pageLoadSeries),
            ("list.bullet", "当前规则", ruleCount, .systemGreen, ruleSeries),
            ("funnel.fill", "过滤器", filterCount, .systemOrange, filterSeries)
        ]
        for (index, tile) in updates {
            tile.update(values[index])
        }
    }

    private func configureView() {
        backgroundColor = .clear
        backgroundConfiguration = UIBackgroundConfiguration.clear()
        selectionStyle = .none

        gridStack.axis = .vertical
        gridStack.spacing = 12
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(gridStack)

        let tileLayout: [(symbol: String, title: String, value: Int, color: UIColor)] = [
            ("shield.fill", "今日拦截", 0, .systemRed),
            ("globe.asia.australia.fill", "今日访问", 0, .systemBlue),
            ("list.bullet", "当前规则", 0, .systemGreen),
            ("funnel.fill", "过滤器", 0, .systemOrange)
        ]
        for index in 0..<4 {
            let tile = StatTileView()
            tile.update((
                tileLayout[index].symbol,
                tileLayout[index].title,
                tileLayout[index].value,
                tileLayout[index].color,
                []
            ))
            tiles.append(tile)
        }
        let top = makeRow([tiles[0], tiles[1]])
        let bottom = makeRow([tiles[2], tiles[3]])
        gridStack.addArrangedSubview(top)
        gridStack.addArrangedSubview(bottom)

        NSLayoutConstraint.activate([
            gridStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            gridStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            gridStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            gridStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
    }

    private func makeRow(_ rowTiles: [StatTileView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: rowTiles)
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        return row
    }
}

/// 单个统计卡片视图：构建一次，后续仅更新数值/标题/趋势图，避免刷新闪动。
private final class StatTileView: UIView {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()
    private let sparkline = SparklineView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(
        _ item: (symbol: String, title: String, value: Int, color: UIColor, series: [Double])
    ) {
        iconView.image = UIImage(
            systemName: item.symbol,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 14,
                weight: .semibold
            )
        )
        iconView.tintColor = item.color
        iconContainer.backgroundColor = item.color.withAlphaComponent(0.14)
        valueLabel.text = item.value.formatted()
        titleLabel.text = item.title
        sparkline.values = item.series
        sparkline.tint = item.color
    }

    private func configureView() {
        backgroundColor = AppColors.surface
        layer.cornerRadius = AppRadius.control + 2
        layer.cornerCurve = .continuous
        ContentBlockCardStyle.applyShadow(to: self)

        iconContainer.layer.cornerRadius = 8
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconContainer)

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        valueLabel.textColor = AppColors.primaryText
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        AppTypography.configure(titleLabel, style: .caption2)
        titleLabel.textColor = AppColors.secondaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        sparkline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sparkline)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconContainer.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            iconContainer.widthAnchor.constraint(equalToConstant: 30),
            iconContainer.heightAnchor.constraint(equalToConstant: 30),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            valueLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 9),
            titleLabel.leadingAnchor.constraint(equalTo: valueLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 1),

            sparkline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sparkline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            sparkline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            sparkline.heightAnchor.constraint(equalToConstant: 26),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 126)
        ])
    }
}

// MARK: - 动作列表项（导入规则 / 网站白名单）

/// 白色圆角卡片列表项：彩色图标块 + 标题/副标题 + 右箭头。
final class ContentBlockActionCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockActionCardCell"

    private let cardView = UIView()
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.forward"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(title: String, subtitle: String?, symbol: String, tint: UIColor) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty != false
        iconView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )
        iconView.tintColor = tint
        iconContainer.backgroundColor = tint.withAlphaComponent(0.12)
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: "，")
        accessibilityTraits = [.button]
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        subtitleLabel.isHidden = true
        accessibilityLabel = nil
        accessibilityTraits = [.button]
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        let updates = {
            self.cardView.alpha = highlighted ? 0.7 : 1
            self.contentView.transform = highlighted
                ? CGAffineTransform(scaleX: 0.992, y: 0.992)
                : .identity
        }
        if animated {
            AppAppearance.animate(
                duration: AppAppearance.quickAnimationDuration,
                animations: updates
            )
        } else {
            updates()
        }
    }

    private func configureView() {
        backgroundColor = .clear
        backgroundConfiguration = UIBackgroundConfiguration.clear()
        selectionStyle = .none

        cardView.backgroundColor = AppColors.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        ContentBlockCardStyle.applyShadow(to: cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        iconContainer.layer.cornerRadius = AppRadius.small
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(iconContainer)

        iconView.contentMode = .center
        iconView.isAccessibilityElement = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        AppTypography.configure(titleLabel, style: .body, weight: .medium)
        titleLabel.textColor = AppColors.primaryText
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        AppTypography.configure(subtitleLabel, style: .caption1)
        subtitleLabel.textColor = AppColors.secondaryText
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(subtitleLabel)

        chevronView.tintColor = .systemGray3
        chevronView.contentMode = .scaleAspectFit
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(chevronView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            iconContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalToConstant: 34),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 13),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -13),

            chevronView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            chevronView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 10)
        ])
    }
}

// MARK: - 趋势图

/// 平滑贝塞尔折线 + 同色渐变填充的小型趋势图。
final class SparklineView: UIView {
    var values: [Double] = [] {
        didSet { setNeedsDisplay() }
    }
    var tint: UIColor = .systemRed {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard values.count >= 2, rect.width > 0, rect.height > 0 else { return }

        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        let step = rect.width / CGFloat(values.count - 1)
        var points: [CGPoint] = []

        if maxValue == minValue {
            // 恒定值（如规则数）：画一条居中平线。
            let y = rect.height * 0.55
            for index in values.indices {
                points.append(CGPoint(x: CGFloat(index) * step, y: y))
            }
        } else {
            let span = maxValue - minValue
            for (index, value) in values.enumerated() {
                let normalized = (value - minValue) / span
                let x = CGFloat(index) * step
                let y = rect.height - CGFloat(normalized) * (rect.height - 3) - 1.5
                points.append(CGPoint(x: x, y: y))
            }
        }

        let path = UIBezierPath()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: mid, controlPoint: previous)
        }
        path.addLine(to: points[points.count - 1])

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        let fill = UIBezierPath(cgPath: path.cgPath)
        fill.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.height))
        fill.addLine(to: CGPoint(x: points[0].x, y: rect.height))
        fill.close()
        fill.addClip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                tint.withAlphaComponent(0.32).cgColor,
                tint.withAlphaComponent(0.0).cgColor
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: rect.minY),
                end: CGPoint(x: 0, y: rect.maxY),
                options: []
            )
        }
        context.restoreGState()

        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        tint.setStroke()
        path.stroke()
    }
}
