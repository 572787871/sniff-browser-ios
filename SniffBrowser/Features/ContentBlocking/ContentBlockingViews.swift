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
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),

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
        pageLoadTitle: String
    ) {
        let values: [(icon: String, trend: String, title: String, value: Int)] = [
            ("stat_red_shield", "chart_red", blockedTitle, blocked),
            ("stat_blue_globe", "chart_blue", pageLoadTitle, pageLoads),
            ("stat_green_rules", "chart_green", "当前规则", ruleCount),
            ("stat_orange_filter", "chart_orange", "过滤器", filterCount)
        ]
        for index in 0..<4 {
            tiles[index].update(
                iconName: values[index].icon,
                trendName: values[index].trend,
                title: values[index].title,
                value: values[index].value
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

        let tileLayout: [(icon: String, trend: String, title: String)] = [
            ("stat_red_shield", "chart_red", "今日拦截"),
            ("stat_blue_globe", "chart_blue", "今日访问"),
            ("stat_green_rules", "chart_green", "当前规则"),
            ("stat_orange_filter", "chart_orange", "过滤器")
        ]
        for index in 0..<tileLayout.count {
            let tile = StatTileView()
            tile.update(
                iconName: tileLayout[index].icon,
                trendName: tileLayout[index].trend,
                title: tileLayout[index].title,
                value: 0
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
    private let trendImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(iconName: String, trendName: String, title: String, value: Int) {
        // 素材直接来自目标参考图：alwaysOriginal，禁止 tint / 拉伸。
        iconImageView.image = UIImage(named: iconName)?
            .withRenderingMode(.alwaysOriginal)
        trendImageView.image = UIImage(named: trendName)?
            .withRenderingMode(.alwaysOriginal)
        valueLabel.text = value.formatted()
        titleLabel.text = title
    }

    private func configureView() {
        backgroundColor = AppColors.surface
        layer.cornerRadius = AppRadius.control + 2
        layer.cornerCurve = .continuous
        ContentBlockCardStyle.applyShadow(to: self)

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.clipsToBounds = false
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

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

        trendImageView.contentMode = .scaleAspectFit
        trendImageView.clipsToBounds = false
        trendImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trendImageView)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconImageView.widthAnchor.constraint(equalToConstant: 42),
            iconImageView.heightAnchor.constraint(equalToConstant: 42),

            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            valueLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: valueLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 1),

            trendImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            trendImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            trendImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            trendImageView.heightAnchor.constraint(equalToConstant: 34),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 126)
        ])
    }
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
