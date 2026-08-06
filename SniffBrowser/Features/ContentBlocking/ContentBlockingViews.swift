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

// MARK: - 总开关卡片

/// 顶部内容拦截总开关：白色圆角卡片 + 蓝色盾牌闪电图标 + UISwitch。
final class ContentBlockMasterCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockMasterCardCell"

    private let cardView = UIView()
    private let iconContainer = UIView()
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
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.07
        cardView.layer.shadowRadius = 10
        cardView.layer.shadowOffset = CGSize(width: 0, height: 3)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        iconContainer.backgroundColor = AppColors.accent
        iconContainer.layer.cornerRadius = AppRadius.control
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.layer.shadowColor = AppColors.accent.cgColor
        iconContainer.layer.shadowOpacity = 0.35
        iconContainer.layer.shadowRadius = 6
        iconContainer.layer.shadowOffset = CGSize(width: 0, height: 3)
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(iconContainer)

        iconView.image = UIImage(
            systemName: "bolt.shield.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

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

            iconContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            iconContainer.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 44),
            iconContainer.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 15),
            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 13),
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

/// 拦截统计卡片：2×2 数据块，每块含彩色图标、大数字、标题与底部趋势图。
final class ContentBlockStatsCardCell: UITableViewCell {
    static let reuseIdentifier = "ContentBlockStatsCardCell"

    private let cardView = UIView()
    private let gridStack = UIStackView()

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
        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let top = makeRow(
            (
                ("shield.lefthalf.filled", blockedTitle, blocked, .systemRed, blockedSeries),
                ("globe", pageLoadTitle, pageLoads, .systemBlue, pageLoadSeries)
            )
        )
        let bottom = makeRow(
            (
                ("list.bullet.rectangle", "当前规则", ruleCount, .systemGreen, ruleSeries),
                ("funnel", "过滤器", filterCount, .systemOrange, filterSeries)
            )
        )
        gridStack.addArrangedSubview(top)
        gridStack.addArrangedSubview(bottom)
    }

    private func makeRow(
        _ items: (
            (symbol: String, title: String, value: Int, color: UIColor, series: [Double]),
            (symbol: String, title: String, value: Int, color: UIColor, series: [Double])
        )
    ) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.addArrangedSubview(makeTile(items.0))
        row.addArrangedSubview(makeTile(items.1))
        return row
    }

    private func makeTile(
        _ item: (symbol: String, title: String, value: Int, color: UIColor, series: [Double])
    ) -> UIView {
        let tile = UIView()
        tile.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.07)
                : UIColor(white: 0.5, alpha: 0.09)
        }
        tile.layer.cornerRadius = AppRadius.control
        tile.layer.cornerCurve = .continuous
        tile.clipsToBounds = true

        let iconContainer = UIView()
        iconContainer.backgroundColor = item.color.withAlphaComponent(0.14)
        iconContainer.layer.cornerRadius = 8
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(iconContainer)

        let iconView = UIImageView(image: UIImage(systemName: item.symbol))
        iconView.tintColor = item.color
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        let valueLabel = UILabel()
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 23, weight: .bold)
        valueLabel.textColor = AppColors.primaryText
        valueLabel.text = item.value.formatted()
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(valueLabel)

        let titleLabel = UILabel()
        AppTypography.configure(titleLabel, style: .caption2)
        titleLabel.textColor = AppColors.secondaryText
        titleLabel.text = item.title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(titleLabel)

        let sparkline = SparklineView()
        sparkline.values = item.series
        sparkline.tint = item.color
        sparkline.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(sparkline)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 11),
            iconContainer.topAnchor.constraint(equalTo: tile.topAnchor, constant: 11),
            iconContainer.widthAnchor.constraint(equalToConstant: 28),
            iconContainer.heightAnchor.constraint(equalToConstant: 28),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            valueLabel.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -6),
            valueLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: valueLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -6),
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 1),

            sparkline.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 10),
            sparkline.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -10),
            sparkline.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -8),
            sparkline.heightAnchor.constraint(equalToConstant: 24),

            tile.heightAnchor.constraint(greaterThanOrEqualToConstant: 122)
        ])
        return tile
    }

    private func configureView() {
        backgroundColor = .clear
        backgroundConfiguration = UIBackgroundConfiguration.clear()
        selectionStyle = .none

        cardView.backgroundColor = AppColors.surface
        cardView.layer.cornerRadius = AppRadius.card
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.07
        cardView.layer.shadowRadius = 10
        cardView.layer.shadowOffset = CGSize(width: 0, height: 3)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        gridStack.axis = .vertical
        gridStack.spacing = 10
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(gridStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            gridStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            gridStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            gridStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            gridStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)
        ])
    }
}

// MARK: - 趋势图

/// 平滑折线 + 渐变填充的小型趋势图。
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

        let fill = UIBezierPath(cgPath: path.cgPath)
        fill.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.height))
        fill.addLine(to: CGPoint(x: points[0].x, y: rect.height))
        fill.close()
        tint.withAlphaComponent(0.16).setFill()
        fill.fill()

        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        tint.setStroke()
        path.stroke()
    }
}
