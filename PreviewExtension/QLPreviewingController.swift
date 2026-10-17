import AppKit
import AVKit
import QuickLookUI

/// 预览控制器：视图层级 + 播放控制。
/// macOS 26 SDK 中 QLPreviewingController 是协议（QLPreviewingViewController 类已被移除），
/// 因此继承 NSViewController 并显式遵守 QuickLookUI.QLPreviewingController 协议；
/// 类名保持 QLPreviewingController 与 Info.plist 的 NSExtensionPrincipalClass 一致。
final class QLPreviewingController: NSViewController, QuickLookUI.QLPreviewingController {

    private let imageView = NSImageView()
    private let playerView = AVPlayerView()
    private let livePhotoButton = NSButton(title: "实况", target: nil, action: nil)

    private var player: AVPlayer?
    private var livpResource: LivpResource?
    private var didPlayToEndObserver: NSObjectProtocol?

    override func loadView() {
        let mainView = NSView(frame: .zero)
        view = mainView

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        mainView.addSubview(imageView)

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.isHidden = true
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        mainView.addSubview(playerView)

        // C5 修正：按示例代码简化，按钮直接加在 mainView，
        // addSubview 顺序保证按钮悬浮在视频/图片之上
        livePhotoButton.translatesAutoresizingMaskIntoConstraints = false
        livePhotoButton.bezelStyle = .rounded
        livePhotoButton.target = self
        livePhotoButton.action = #selector(togglePlay)
        mainView.addSubview(livePhotoButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: mainView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),

            playerView.topAnchor.constraint(equalTo: imageView.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            livePhotoButton.leadingAnchor.constraint(equalTo: mainView.leadingAnchor, constant: 16),
            livePhotoButton.bottomAnchor.constraint(equalTo: mainView.bottomAnchor, constant: -16),
        ])
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        resetResources()

        do {
            let resource = try LivpParser.parseLivp(fileURL: url)
            livpResource = resource
            imageView.image = NSImage(contentsOf: resource.coverURL)

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

            handler(nil)
        } catch {
            handler(error)
        }
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

    /// 切换文件 / 关闭预览时的强制释放点：AVPlayer 释放 + 临时目录清理 + 通知移除
    private func resetResources() {
        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }
        player?.pause()
        player = nil
        playerView.player = nil
        playerView.isHidden = true
        imageView.image = nil

        if let resource = livpResource {
            LivpParser.cleanupTempDir(resource.tempDir)
            livpResource = nil
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        resetResources()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateButtonAppearance()
    }

    // C2 修正：暗黑模式适配，变量名统一为 livePhotoButton
    private func updateButtonAppearance() {
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        livePhotoButton.contentTintColor = isDark ? .white : .black
    }
}
