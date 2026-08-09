import UIKit

// MARK: - 区块标题（琥珀信号条 + 标题 + 可选右侧控件）

/// 内容拦截页的区块标题：左侧品牌信号条 + 加粗标题，右侧可挂筛选按钮。
final class ContentBlockSectionHeaderView: UIView {
    private let barView = UIView()
    private let titleLabel = UILabel()

    init(title: String, trailing: UIView? = nil) {
        super.init(frame: .zero)

        barView.backgroundColor = AppColors.accent
        barView.layer.cornerRadius = 2
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
            barView.widthAnchor.constraint(equalToConstant: 4),
            barView.heightAnchor.constraint(equalToConstant: 16),
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
        view.layer.borderWidth = AppMetrics.separatorHeight
        view.layer.borderColor = AppColors.separator.cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.035
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowPath = nil
    }
}

// MARK: - 总开关卡片

/// 顶部内容拦截总开关：暖纸卡片 + 原生图标与开关。
final class ContentBlockMasterCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockMasterCardCell"

    private let cardView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggleButton = UISwitch()
    private var onChange: ((Bool) -> Void)?
    private var isOn = true

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
        self.isOn = isOn
        toggleButton.setOn(isOn, animated: false)
        self.onChange = onChange
        self.accessibilityIdentifier = accessibilityIdentifier
        toggleButton.accessibilityIdentifier = "\(accessibilityIdentifier).switch"
        accessibilityLabel = "\(title)，\(subtitle)"
        accessibilityValue = isOn ? "已开启" : "已关闭"
        toggleButton.accessibilityLabel = title
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onChange = nil
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        accessibilityValue = nil
    }

    @objc private func toggleChanged() {
        isOn = toggleButton.isOn
        accessibilityValue = isOn ? "已开启" : "已关闭"
        onChange?(isOn)
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

        iconView.image = UIImage(
            systemName: "shield.lefthalf.filled",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 27, weight: .medium)
        )
        iconView.tintColor = AppColors.accent
        iconView.backgroundColor = AppColors.accentFill
        iconView.layer.cornerRadius = AppRadius.control
        iconView.layer.cornerCurve = .continuous
        iconView.contentMode = .center
        iconView.clipsToBounds = true
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

        toggleButton.onTintColor = AppColors.accent
        toggleButton.addTarget(
            self,
            action: #selector(toggleChanged),
            for: .touchUpInside
        )
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(toggleButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 52),
            iconView.heightAnchor.constraint(equalToConstant: 52),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 15),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggleButton.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggleButton.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -14),

            toggleButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            toggleButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            toggleButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 51),
            toggleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 31)
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
        let values: [(icon: String, title: String, value: Int, series: [Double], color: UIColor)] = [
            ("shield.slash", blockedTitle, blocked, blockedSeries, ContentBlockChartColors.blocked),
            ("globe", pageLoadTitle, pageLoads, pageLoadSeries, ContentBlockChartColors.pageLoads),
            ("list.bullet.rectangle", "当前规则", ruleCount, ruleSeries, ContentBlockChartColors.rules),
            ("line.3.horizontal.decrease", "过滤器", filterCount, filterSeries, ContentBlockChartColors.filters)
        ]
        for index in 0..<4 {
            tiles[index].update(
                iconName: values[index].icon,
                title: values[index].title,
                value: values[index].value,
                series: values[index].series,
                color: values[index].color
            )
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

        let tileLayout: [(icon: String, title: String, color: UIColor)] = [
            ("shield.slash", "今日拦截", ContentBlockChartColors.blocked),
            ("globe", "今日访问", ContentBlockChartColors.pageLoads),
            ("list.bullet.rectangle", "当前规则", ContentBlockChartColors.rules),
            ("line.3.horizontal.decrease", "过滤器", ContentBlockChartColors.filters)
        ]
        for index in 0..<tileLayout.count {
            let tile = StatTileView()
            tile.update(
                iconName: tileLayout[index].icon,
                title: tileLayout[index].title,
                value: 0,
                series: [],
                color: tileLayout[index].color
            )
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
    private let iconImageView = UIImageView()
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()
    private let sparkline = SparklineView()
    private let textStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(
        iconName: String,
        title: String,
        value: Int,
        series: [Double],
        color: UIColor
    ) {
        iconImageView.image = UIImage(
            systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        iconImageView.tintColor = color
        iconImageView.backgroundColor = color.withAlphaComponent(0.12)
        valueLabel.text = value.formatted()
        titleLabel.text = title
        sparkline.values = series
        sparkline.tint = color
    }

    private func configureView() {
        backgroundColor = AppColors.surface
        layer.cornerRadius = AppRadius.control + 2
        layer.cornerCurve = .continuous
        ContentBlockCardStyle.applyShadow(to: self)

        iconImageView.contentMode = .center
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = AppRadius.control
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = AppColors.primaryText
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        AppTypography.configure(titleLabel, style: .caption2)
        titleLabel.textColor = AppColors.secondaryText

        // 右侧文本块：数字在上、说明文字在下，与图标同一行垂直居中。
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(valueLabel)
        textStack.addArrangedSubview(titleLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        // 真实数据趋势曲线（拦截日期数量变化），托底横跨卡片宽度。
        sparkline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sparkline)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            iconImageView.widthAnchor.constraint(equalToConstant: 38),
            iconImageView.heightAnchor.constraint(equalToConstant: 38),

            textStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            textStack.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),

            sparkline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sparkline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sparkline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            sparkline.heightAnchor.constraint(equalToConstant: 38),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 132)
        ])
    }
}

// MARK: - 真实数据趋势曲线

/// 参考图配色 + 逐日数据绘制的平滑波浪曲线（无黑底、无静态图片）。
final class SparklineView: UIView {
    var values: [Double] = [] {
        didSet { setNeedsDisplay() }
    }
    var tint: UIColor = AppColors.danger {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ rect: CGRect) {
        guard values.count >= 2, rect.width > 0, rect.height > 0 else { return }
        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        let step = rect.width / CGFloat(values.count - 1)
        var points: [CGPoint] = []

        if maxValue == minValue {
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
                tint.withAlphaComponent(0.28).cgColor,
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

/// 与 Paper Signal 暖纸色协调的语义趋势线。
enum ContentBlockChartColors {
    static let blocked = AppColors.danger
    static let pageLoads = AppColors.accent
    static let rules = AppColors.success
    static let filters = UIColor(red: 0.596, green: 0.463, blue: 0.298, alpha: 1)
}

// MARK: - 动作列表项（导入规则 / 网站白名单）

/// 白色圆角卡片列表项：素材图标 + 标题/副标题 + 右箭头。
final class ContentBlockActionCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockActionCardCell"

    private let cardView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevronView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(title: String, subtitle: String?, imageName: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty != false
        let symbol = imageName == "import_rule"
            ? "square.and.arrow.down"
            : "checkmark.shield"
        iconView.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        )
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

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = AppColors.accent
        iconView.backgroundColor = AppColors.accentFill
        iconView.layer.cornerRadius = AppRadius.control
        iconView.layer.cornerCurve = .continuous
        iconView.clipsToBounds = true
        iconView.isAccessibilityElement = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(iconView)

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

        chevronView.image = UIImage(systemName: "chevron.right")
        chevronView.tintColor = AppColors.tertiaryText
        chevronView.contentMode = .scaleAspectFit
        chevronView.clipsToBounds = false
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(chevronView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 38),
            iconView.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
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
