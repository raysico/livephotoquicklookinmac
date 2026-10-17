import AppKit
import AVKit

/// 右侧内容区：HEIC 封面（可缩放平移）+ 左下角「实况」按钮 + 视频播放。
final class ContentViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let imageView = NSImageView()
    private let playerView = AVPlayerView()
    private let livePhotoButton = NSButton(title: "实况", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private var player: AVPlayer?
    private var item: LivePhotoItem?
    private var didPlayToEndObserver: NSObjectProtocol?
    private var didFitZoom = false

    override func loadView() {
        let root = NSView()
        view = root

        // 滚动视图 + 封面（documentView 用 frame 方式，支持缩放/平移）
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.02
        scrollView.maxMagnification = 8.0
        scrollView.drawsBackground = true
        root.addSubview(scrollView)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        scrollView.documentView = imageView

        // 视频层（覆盖在封面之上）
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.isHidden = true
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        root.addSubview(playerView)

        // 「实况」按钮
        livePhotoButton.translatesAutoresizingMaskIntoConstraints = false
        livePhotoButton.bezelStyle = .rounded
        livePhotoButton.target = self
        livePhotoButton.action = #selector(togglePlay)
        livePhotoButton.isHidden = true
        root.addSubview(livePhotoButton)

        // 空状态 / 错误提示
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "打开或拖入 .livp 文件开始预览"
        root.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            playerView.topAnchor.constraint(equalTo: root.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            livePhotoButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            livePhotoButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

            statusLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
    }

    // MARK: - 内容切换

    func show(_ item: LivePhotoItem?) {
        reset()
        self.item = item
        guard let item = item else {
            statusLabel.stringValue = "打开或拖入 .livp 文件开始预览"
            statusLabel.isHidden = false
            return
        }
        if let error = item.load() {
            statusLabel.stringValue = "无法预览：\(error.localizedDescription)"
            statusLabel.isHidden = false
            return
        }
        guard let resource = item.resource else { return }

        statusLabel.isHidden = true
        livePhotoButton.isHidden = false

        if let image = NSImage(contentsOf: resource.coverURL) {
            imageView.image = image
            imageView.frame = NSRect(origin: .zero, size: image.size)
            didFitZoom = false
            zoomToFitIfNeeded()
        }

        let avPlayer = AVPlayer(url: resource.videoURL)
        player = avPlayer
        playerView.player = avPlayer
        if let currentItem = avPlayer.currentItem {
            didPlayToEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.videoDidFinish()
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        zoomToFitIfNeeded()
    }

    private func zoomToFitIfNeeded() {
        guard !didFitZoom,
              let image = imageView.image,
              image.size.width > 0,
              scrollView.bounds.width > 0 else { return }
        let fit = min(scrollView.bounds.width / image.size.width,
                      scrollView.bounds.height / image.size.height)
        let magnification = min(max(fit, scrollView.minMagnification), scrollView.maxMagnification)
        scrollView.magnification = magnification
        didFitZoom = true
    }

    @objc private func togglePlay() {
        guard let player = player else { return }
        if player.rate > 0 {
            player.pause()
            playerView.isHidden = true
        } else {
            player.seek(to: .zero)
            player.play()
            playerView.isHidden = false
        }
    }

    @objc private func videoDidFinish() {
        player?.pause()
        playerView.isHidden = true
    }

    private func reset() {
        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }
        player?.pause()
        player = nil
        playerView.player = nil
        playerView.isHidden = true
        imageView.image = nil
        livePhotoButton.isHidden = true
        item = nil
    }

    /// 供 AppDelegate 在窗口关闭 / 退出时调用，清理临时目录
    func teardown() {
        reset()
    }
}
