import UIKit

// MARK: - 区块标题（蓝色竖杠 + 标题 + 可选右侧控件）

/// 内容拦截页的区块标题：左侧蓝色小竖杠 + 加粗标题，右侧可挂筛选按钮。
final class ContentBlockSectionHeaderView: UIView {
    private let barView = UIImageView()
    private let titleLabel = UILabel()

    init(title: String, trailing: UIView? = nil) {
        super.init(frame: .zero)

        // 分区蓝色竖条使用 section_bar 素材，禁止 tint。
        barView.image = UIImage(named: "section_bar")?
            .withRenderingMode(.alwaysOriginal)
        barView.contentMode = .scaleAspectFit
        barView.clipsToBounds = false
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
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.07
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 3)
        view.layer.shadowPath = nil
    }
}

// MARK: - 总开关卡片

/// 顶部内容拦截总开关：白色圆角卡片 + shield_blue_main + toggle_on 素材。
final class ContentBlockMasterCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockMasterCardCell"

    private let cardView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggleButton = UIButton(type: .custom)
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
        isOn.toggle()
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

        // 素材直接来自目标参考图，禁止 tint / 模板渲染 / 拉伸。
        iconView.image = UIImage(named: "shield_blue_main")?
            .withRenderingMode(.alwaysOriginal)
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = false
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

        // 主开关：toggle_on 素材，保持可点击切换功能。
        toggleButton.setImage(
            UIImage(named: "toggle_on")?.withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        toggleButton.imageView?.contentMode = .scaleAspectFit
        toggleButton.clipsToBounds = false
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
            toggleButton.widthAnchor.constraint(equalToConstant: 52),
            toggleButton.heightAnchor.constraint(equalToConstant: 32)
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
            ("stat_red_shield", blockedTitle, blocked, blockedSeries, ContentBlockChartColors.blocked),
            ("stat_blue_globe", pageLoadTitle, pageLoads, pageLoadSeries, ContentBlockChartColors.pageLoads),
            ("stat_green_rules", "当前规则", ruleCount, ruleSeries, ContentBlockChartColors.rules),
            ("stat_orange_filter", "过滤器", filterCount, filterSeries, ContentBlockChartColors.filters)
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
            ("stat_red_shield", "今日拦截", ContentBlockChartColors.blocked),
            ("stat_blue_globe", "今日访问", ContentBlockChartColors.pageLoads),
            ("stat_green_rules", "当前规则", ContentBlockChartColors.rules),
            ("stat_orange_filter", "过滤器", ContentBlockChartColors.filters)
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
        // 素材直接来自目标参考图：alwaysOriginal，禁止 tint / 拉伸。
        iconImageView.image = UIImage(named: iconName)?
            .withRenderingMode(.alwaysOriginal)
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

        // 素材直接来自目标参考图：alwaysOriginal，禁止 tint / 拉伸。
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.clipsToBounds = false
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
    var tint: UIColor = .systemRed {
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

/// 参考图趋势线配色（从素材包 chart_* 采样）。
enum ContentBlockChartColors {
    static let blocked = UIColor(red: 228 / 255, green: 123 / 255, blue: 138 / 255, alpha: 1)
    static let pageLoads = UIColor(red: 69 / 255, green: 130 / 255, blue: 224 / 255, alpha: 1)
    static let rules = UIColor(red: 97 / 255, green: 194 / 255, blue: 127 / 255, alpha: 1)
    static let filters = UIColor(red: 235 / 255, green: 162 / 255, blue: 98 / 255, alpha: 1)
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
        // 素材直接来自目标参考图：alwaysOriginal，禁止 tint / 拉伸。
        iconView.image = UIImage(named: imageName)?
            .withRenderingMode(.alwaysOriginal)
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
        iconView.clipsToBounds = false
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

        // 列表箭头使用 chevron_right 素材，禁止 tint。
        chevronView.image = UIImage(named: "chevron_right")?
            .withRenderingMode(.alwaysOriginal)
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
