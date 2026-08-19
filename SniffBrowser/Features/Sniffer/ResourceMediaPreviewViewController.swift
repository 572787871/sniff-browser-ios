import AVKit
import UIKit

/// A small stateful container around AVPlayerViewController.
///
/// The existing loopback playback server remains responsible for fetching the
/// media with the page's request context. This controller only owns the user
/// visible playback state, so a failed AVPlayerItem does not silently become a
/// dead black player and a user can start a download without leaving the
/// resource flow.
@MainActor
final class ResourceMediaPreviewViewController: UIViewController {
    private let titleText: String
    private let playbackURL: URL
    private let downloadTitle: String
    private let onDownload: (() -> Void)?

    private let playerController = AVPlayerViewController()
    private let titleLabel = UILabel()
    private let downloadButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let statusView = UIView()
    private let statusLabel = UILabel()
    private let statusDetailLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var observations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []

    init(
        title: String,
        playbackURL: URL,
        downloadTitle: String,
        onDownload: (() -> Void)?
    ) {
        titleText = title
        self.playbackURL = playbackURL
        self.downloadTitle = downloadTitle
        self.onDownload = onDownload
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePlayer()
        configureOverlay()
        configureConstraints()
        updateStatus(.preparing)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        player?.play()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            player?.pause()
        }
    }

    deinit {
        observations.forEach { $0.invalidate() }
        notificationTokens.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    private func configurePlayer() {
        addChild(playerController)
        playerController.view.translatesAutoresizingMaskIntoConstraints = false
        playerController.view.backgroundColor = .black
        playerController.showsPlaybackControls = true
        playerController.allowsPictureInPicturePlayback = true
        view.addSubview(playerController.view)
        playerController.didMove(toParent: self)

        preparePlayer()
    }

    private func preparePlayer() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        notificationTokens.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        notificationTokens.removeAll()

        let item = AVPlayerItem(url: playbackURL)
        item.preferredForwardBufferDuration = 5
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        playerController.player = player
        playerItem = item
        self.player = player

        observations.append(
            item.observe(\AVPlayerItem.status, options: [.initial, .new]) {
                [weak self] item, _ in
                Task { @MainActor [weak self] in
                    self?.handleItemStatus(item)
                }
            }
        )
        observations.append(
            item.observe(\AVPlayerItem.isPlaybackLikelyToKeepUp, options: [.new]) {
                [weak self] item, _ in
                guard item.isPlaybackLikelyToKeepUp else { return }
                Task { @MainActor [weak self] in
                    self?.updateStatus(.playing)
                }
            }
        )
        observations.append(
            item.observe(\AVPlayerItem.isPlaybackBufferEmpty, options: [.new]) {
                [weak self] item, _ in
                guard item.isPlaybackBufferEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.updateStatus(.buffering)
                }
            }
        )
        observations.append(
            player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) {
                [weak self] player, _ in
                Task { @MainActor [weak self] in
                    self?.handleTimeControlStatus(player)
                }
            }
        )
        let failureToken: NSObjectProtocol = NotificationCenter.default.addObserver(
            forName: Notification.Name.AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] (notification: Notification) in
            let error = notification.userInfo?
                [AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                self?.showPlaybackFailure(error)
            }
        }
        notificationTokens.append(failureToken)
    }

    private func configureOverlay() {
        let topBar = UIStackView(arrangedSubviews: [titleLabel, downloadButton, closeButton])
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.spacing = AppSpacing.xs
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        titleLabel.text = titleText
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if onDownload != nil {
            downloadButton.setTitle(downloadTitle, for: .normal)
            downloadButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
            downloadButton.tintColor = .white
            downloadButton.setTitleColor(.white, for: .normal)
            downloadButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
            downloadButton.accessibilityIdentifier = "resource.media-preview.download"
            downloadButton.addTarget(self, action: #selector(downloadPressed), for: .touchUpInside)
        } else {
            downloadButton.isHidden = true
        }
        downloadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        downloadButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "关闭播放器"
        closeButton.accessibilityIdentifier = "resource.media-preview.close"
        closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        closeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        statusView.backgroundColor = UIColor.black.withAlphaComponent(0.74)
        statusView.layer.cornerRadius = 16
        statusView.layer.cornerCurve = .continuous
        statusView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusView)

        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel, statusDetailLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(stack)

        activityIndicator.color = .white
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusDetailLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        statusDetailLabel.font = .preferredFont(forTextStyle: .caption1)
        statusDetailLabel.adjustsFontForContentSizeCategory = true
        statusDetailLabel.numberOfLines = 0
        statusDetailLabel.textAlignment = .center
        retryButton.setTitle("重试播放", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        retryButton.layer.cornerRadius = AppRadius.control
        retryButton.layer.borderWidth = 1
        retryButton.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        retryButton.accessibilityIdentifier = "resource.media-preview.retry"
        retryButton.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
    }

    private func configureConstraints() {
        guard let topBar = view.subviews.first(where: { $0 is UIStackView }) else { return }
        NSLayoutConstraint.activate([
            playerController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            statusView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            statusView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            statusView.heightAnchor.constraint(greaterThanOrEqualToConstant: 128)
        ])

        guard let stack = statusView.subviews.first else { return }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: statusView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: statusView.bottomAnchor, constant: -18)
        ])
    }

    private enum PlaybackState {
        case preparing
        case buffering
        case playing
        case failed(String)
    }

    private func handleItemStatus(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            if player?.timeControlStatus == .playing {
                updateStatus(.playing)
            }
        case .failed:
            showPlaybackFailure(item.error)
        case .unknown:
            updateStatus(.preparing)
        @unknown default:
            updateStatus(.preparing)
        }
    }

    private func handleTimeControlStatus(_ player: AVPlayer) {
        switch player.timeControlStatus {
        case .playing:
            updateStatus(.playing)
        case .waitingToPlayAtSpecifiedRate:
            updateStatus(.buffering)
        case .paused:
            if player.currentItem?.status == .readyToPlay {
                statusView.isHidden = true
            }
        @unknown default:
            updateStatus(.preparing)
        }
    }

    private func updateStatus(_ state: PlaybackState) {
        switch state {
        case .preparing:
            statusView.isHidden = false
            activityIndicator.startAnimating()
            statusLabel.text = "正在准备播放"
            statusDetailLabel.text = "正在连接当前视频资源…"
            retryButton.isHidden = true
        case .buffering:
            statusView.isHidden = false
            activityIndicator.startAnimating()
            statusLabel.text = "正在缓冲"
            statusDetailLabel.text = "网络较慢时可以稍等片刻"
            retryButton.isHidden = true
        case .playing:
            statusView.isHidden = true
            activityIndicator.stopAnimating()
            retryButton.isHidden = true
        case let .failed(message):
            statusView.isHidden = false
            activityIndicator.stopAnimating()
            statusLabel.text = "无法播放此视频"
            statusDetailLabel.text = message
            retryButton.isHidden = false
        }
    }

    private func showPlaybackFailure(_ error: Error?) {
        let message = Self.userFacingErrorMessage(error)
        updateStatus(.failed(message))
    }

    private static func userFacingErrorMessage(_ error: Error?) -> String {
        guard let error else {
            return "视频地址可能已失效，或网站拒绝了播放器请求。"
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "网络请求失败（\(nsError.code)），可以重试或改为下载。"
        }
        return "视频地址可能已失效，或网站拒绝了播放器请求。"
    }

    @objc private func closePressed() {
        dismiss(animated: true)
    }

    @objc private func retryPressed() {
        updateStatus(.preparing)
        preparePlayer()
        player?.play()
    }

    @objc private func downloadPressed() {
        guard let onDownload else { return }
        dismiss(animated: true, completion: onDownload)
    }
}
