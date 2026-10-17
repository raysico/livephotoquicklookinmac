# LivePhotoQuickLook — macOS QuickLook PreviewExtension 开发文档（MVP）

**项目定位：**参考 AVIFQuickLook 工程思路，新建 macOS App \+ PreviewExtension Appex（Swift），让访达按空格即可预览 **\.livp** 实况照片：默认展示 HEIC 静态封面，左下角「实况」按钮控制 MOV 视频播放。

**MVP 边界：**仅支持 \.livp 单一文件；不做 HEIC\+MOV 配对、不做 ThumbnailExtension、不做长按手势。

**最低部署目标：**macOS 12 Monterey（HEIC 原生支持完善、AVKit 稳定）。

# 整体架构

主壳 App 仅作为 Appex 扩展的宿主，本身无业务 UI；所有预览逻辑运行在 `quicklookd` 托管的独立扩展进程中。扩展通过系统自带 Framework 完成图片解码、视频播放与 zip 解压，**不嵌入任何第三方静态库**，以保证沙盒签名与公证顺利、Appex 体积极小。

```text
LivePhotoQuickLook（主壳 App，仅承载 Appex）
└── PreviewExtension（Appex Target: QLPreviewingController）
    ├─ QLPreviewingController.swift   // 预览控制器：视图层级 + 播放控制
    ├─ LivpParser.swift              // libarchive 解压 livp，分离 HEIC + MOV
    └─ Info.plist                    // 注册 UTI: com.apple.live-photo-bundle

```

## 视图层级

```text
QLPreviewingController.view
└── contentView
    ├─ imageView: NSImageView        // 底层，铺满，展示 HEIC 静态封面
    ├─ playerView: AVPlayerView      // 上层叠加，默认 hidden，播放 MOV
    └─ overlayControlsView           // 悬浮控件
        └─ livePhotoButton: NSButton // 左下角「实况」按钮，切换播放/暂停

```

## 依赖清单（全部系统原生）

|库 / Framework|用途|链接方式|
|---|---|---|
|AppKit|NSViewController、NSView、NSImageView、NSButton|系统 Framework|
|AVKit / AVFoundation|AVPlayer、AVPlayerView，播放 livp 内 HEVC MOV|系统 Framework|
|ImageIO|HEIC 图片解码、元数据读取|系统 Framework|
|libarchive\.tbd|读取 livp（zip 归档），遍历内部条目|链接系统 tbd，**禁止静态打包**|

**禁止：**引入外部编译好的 libarchive 静态库、libheif、libraw 等——会导致公证失败、Appex 体积膨胀、签名校验报错。

# 前置环境准备

## 开发工具

- Xcode 14\+，macOS 12\+ 部署目标

- Apple Developer 账号（本地开发可免费；对外分发必须付费账号用于公证 Notarization）

- 测试素材：iPhone 导出的 \.livp 文件若干

## 调试命令（终端）

```bash
# 重启 quicklookd，重载扩展
qlmanage -r

# 直接预览指定 livp，用于调试
qlmanage -p /path/to/xxx.livp

# 查看当前已注册的 QuickLook 插件
qlmanage -m plugins

```

# Xcode 工程创建步骤

## 创建主壳 App

1. Xcode → New Project → macOS → App，命名 `LivePhotoQuickLook`，Language 选 Swift。

2. 取消勾选 Use Core Data / Tests（MVP 精简）。

3. 壳 App 可删除默认 Window——它仅作为 Appex 的宿主。

## 添加 PreviewExtension Target

1. File → New → Target → macOS → Quick Look Preview Extension。

2. Product Name 填 `PreviewExtension`，Language 选 Swift，Deployment Target 与主 App 一致。

3. Xcode 自动生成 `QLPreviewingController.swift` 与扩展独立 Info\.plist。

**扩展有独立 Info\.plist**——UTI 注册、支持类型必须改 PreviewExtension 下的 plist，不是主 App 的 plist。

## 链接 libarchive\.tbd

选中 PreviewExtension target → Build Phases → Link Binary With Libraries → 点 \+，搜索 `libarchive.tbd` 添加。

# Info\.plist 配置（核心）

打开 `PreviewExtension/Info.plist`，右键 Open As → Source Code，确认包含以下片段，把 `com.apple.live-photo-bundle` 注册为支持的内容类型：

```xml
<key>QLSupportedContentTypes</key>
<array>
    <string>com.apple.live-photo-bundle</string>
</array>
<key>NSExtension</key>
<dict>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).QLPreviewingController</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.quicklook.preview</string>
</dict>

```

# 核心代码

## LivpParser\.swift — livp 解压模块

职责：用系统 libarchive 打开 livp zip 包，遍历内部条目，把图片（heic/jpg）识别为封面、mov 识别为视频，写入扩展临时目录并返回资源 URL。用完必须调用 `cleanupTempDir` 清理。

```swift
import Foundation
import libarchive

enum LivpParseError: Error {
    case openFailed
    case noImageFound
    case noVideoFound
    case readEntryFailed
}

struct LivpResource {
    let coverURL: URL
    let videoURL: URL
    let tempDir: URL
}

class LivpParser {
    static func parseLivp(fileURL: URL) throws -> LivpResource {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)

        var archive: OpaquePointer? = archive_read_new()
        archive_read_support_format_zip(archive)
        defer { archive_read_free(archive) }

        guard archive_read_open_filename(archive, fileURL.path, 10240) == ARCHIVE_OK else {
            throw LivpParseError.openFailed
        }

        var coverURL: URL?
        var videoURL: URL?
        var entry: OpaquePointer?

        while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
            guard let entry = entry else { continue }
            let entryName = String(cString: archive_entry_pathname(entry))
            let entryURL = tempDir.appendingPathComponent(entryName)

            guard let fp = fopen(entryURL.path, "wb") else { continue }
            var buf = [UInt8](repeating: 0, count: 8192)
            while true {
                let r = archive_read_data(archive, &buf, buf.count)
                if r <= 0 { break }
                fwrite(&buf, 1, Int(r), fp)
            }
            fclose(fp)

            let ext = (entryName as NSString).pathExtension.lowercased()
            if ext == "heic" || ext == "jpg" || ext == "jpeg" {
                coverURL = entryURL
            } else if ext == "mov" {
                videoURL = entryURL
            }
        }

        guard let cover = coverURL, let video = videoURL else {
            throw LivpParseError.noImageFound
        }
        return LivpResource(coverURL: cover, videoURL: video, tempDir: tempDir)
    }

    static func cleanupTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}

```

**注意：**livp 内部文件名不固定，必须按后缀遍历识别，不能硬编码 `image.heic`。

## QLPreviewingController\.swift — 预览控制器

核心生命周期：`preparePreviewOfFile` 加载新文件前先 `resetResources()` 释放上一个 AVPlayer 与临时目录；视频播放结束自动回到静态封面；视图消失时再释放一次。

```swift
import AppKit
import AVKit
import QuickLook

class QLPreviewingController: QLPreviewingController {
    private let imageView = NSImageView()
    private let playerView = AVPlayerView()
    private let livePhotoButton = NSButton(
        title: "实况", target: nil, action: #selector(togglePlay))

    private var player: AVPlayer?
    private var livpResource: LivpResource?

    override func loadView() {
        let mainView = NSView(frame: .zero)
        self.view = mainView

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        mainView.addSubview(imageView)

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.isHidden = true
        playerView.controlsStyle = .none   // 不用 AVKit 自带进度条
        mainView.addSubview(playerView)

        livePhotoButton.translatesAutoresizingMaskIntoConstraints = false
        livePhotoButton.bezelStyle = .rounded
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

            livePhotoButton.leadingAnchor.constraint(
                equalTo: mainView.leadingAnchor, constant: 16),
            livePhotoButton.bottomAnchor.constraint(
                equalTo: mainView.bottomAnchor, constant: -16),
        ])
    }

    override func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        resetResources()

        do {
            let resource = try LivpParser.parseLivp(fileURL: url)
            self.livpResource = resource
            imageView.image = NSImage(contentsOf: resource.coverURL)

            let avPlayer = AVPlayer(url: resource.videoURL)
            self.player = avPlayer
            playerView.player = avPlayer

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(videoDidFinish),
                name: .AVPlayerItemDidPlayToEndTime,
                object: avPlayer.currentItem)

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

    private func resetResources() {
        player?.pause()
        player = nil
        playerView.player = nil
        playerView.isHidden = true
        imageView.image = nil

        if let res = livpResource {
            LivpParser.cleanupTempDir(res.tempDir)
            livpResource = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        resetResources()
    }
}

```

## 暗黑模式适配补丁（可选）

```swift
override func viewDidAppear() {
    super.viewDidAppear()
    updateButtonAppearance()
}

private func updateButtonAppearance() {
    guard #available(macOS 10.14, *) else { return }
    let isDark = view.effectiveAppearance.bestMatch(
        from: [.darkAqua, .aqua]) == .darkAqua
    livePhotoViewButton.contentTintColor = isDark ? .white : .black
}

```

# MVP 验收清单

Xcode 选择 Scheme = PreviewExtension 运行，或终端执行 `qlmanage -p test.livp`，逐项验证：

- 

    * [ ] 空格打开 \.livp，正常显示 HEIC 静态封面

- 

    * [ ] 点击左下角「实况」按钮，MOV 视频开始播放

- 

    * [ ] 视频播放完毕，自动隐藏视频层，回到静态封面

- 

    * [ ] 再次点击按钮，可以从头重播

- 

    * [ ] 切换到别的文件 / 关闭预览，AVPlayer 释放、临时目录自动删除

- 

    * [ ] 滚轮缩放、拖拽平移图片正常（NSImageView 原生行为）

# 打包、签名与公证

1. Archive 工程 → 导出为 Developer ID 签名的 \.app。

2. 公证（Notarization）：macOS 强制要求，否则用户打开会报「未识别开发者」。

3. 公证成功后执行 stapler 装订。

4. 交付产物：`.app` 包，用户拖入 `/Applications` 即可。

5. 首次安装后如未识别，终端执行一次 `qlmanage -r`。

# 路线图

## MVP1（当前实现范围）

- 仅支持 \.livp 单一文件

- 静态封面 \+ 左下角实况按钮控制播放/暂停

- 自动释放 AVPlayer、清理临时文件

- 不做 ThumbnailExtension、不做 HEIC\+MOV 配对、不做长按手势

## MVP2（迭代）

- 增加 `NSPressGestureRecognizer` 长按触控板播放（与按钮双交互）

- 增加 ThumbnailExtension：访达图标缩略图，角落叠加「实况」标记

- 配对模式：读取 HEIC MakerNote 中的 assetIdentifier，同目录匹配 MOV

## MVP3（增强）

- 色彩管理、EXIF 方向修正

- 音量控制

- 循环播放选项

# 风险与坑清单

|风险点|应对|
|---|---|
|**AVPlayer 生命周期**|切换文件、关闭预览必须释放 player，否则 quicklookd 内存泄漏崩溃。`resetResources()` 是强制调用点。|
|**临时文件**|解压产物写入 Appex 临时目录，用完必须删除；沙盒不能读写用户任意目录。|
|**损坏 livp 包**|libarchive 读取失败必须 catch 异常返回给 completionHandler，不能让扩展崩溃。|
|**暗黑模式**|按钮外观需监听 NSAppearance 变化，否则暗色模式下按钮不可见。|
|**quicklookd 回收**|系统随时可能杀掉扩展进程，不要保存跨预览会话的全局状态。|
|**并发预览**|quicklookd 可能同时加载多个实例，每个实例用独立 UUID 临时目录做资源隔离。|

# 参考项目

- **AVIFQuickLook**（dreampiggy，MIT）——工程结构、UTI 注册、打包公证脚本思路来源。注意它是旧版 \.qlgenerator，仅作参考，不直接复用产物。

- **lap**（julyx10，MIT）——livp zip 解析逻辑、HEIC MakerNote assetIdentifier 配对思路参考。它是独立 App，不直接搬入 Appex，仅复用算法。

- Apple WWDC19 Session 719《Building Quick Look Extensions》。

- Apple SamplePhotoEditingExtension（PHLivePhotoView 官方示例）。

# 附录：公证（Notarization）费用与账号说明

**一句话结论：**公证云端扫描服务本身**无单独收费**；但执行公证的前提是拥有 **Apple Developer Program 付费会员账号**（个人年费 99 美元，国内约 ¥688/年），只有付费会员才能申请 Developer ID 签名证书，用于 App / Appex 签名并提交公证。

## 公证服务本身不额外收费

一旦已经是付费开发者会员，以下全程不再单独扣费：

- 上传 App / Appex 包到苹果公证服务

- 云端恶意代码扫描

- 生成公证票据、执行 `stapler staple` 装订凭证

没有按次、按包、按版本计费；同账号可无限次提交公证（仅存在服务速率限流，个人项目一般碰不到）。

## 必须付费开发者账号才能公证

|账号类型|能否公证|用途|
|---|---|---|
|**免费 Apple ID**|❌ 不能|只能本地编译调试，拿不到 Developer ID 证书，无法提交公证|
|**Apple Developer Program（付费）**|✅ 可以|年费 99 美元，申领 Developer ID 证书，签名 \+ 公证 \+ staple，对外分发|
|**非营利 / 教育 / 政府机构**|✅ 可申请会费豁免|满足条件可免年费|

## 本地开发 vs 对外分发（对 MVP 很关键）

**本地开发调试（仅自己电脑）**

- 普通 Apple ID 即可

- 不需要付费账号

- 不需要公证

- Xcode Run、`qlmanage` 调试不受 Gatekeeper 限制

**对外分发给其他用户（Release 包）**

- 必须付费开发者账号

- Developer ID 证书签名 App \+ Appex

- 提交苹果公证 \+ staple 装订

- 否则 Gatekeeper 拦截，用户需手动在系统设置放行

## 开源项目备选路径

如果打算开源这个 LivePhotoQuickLook，但不想持续承担 99 美元年费：

1. 仅发布源码，让用户自行下载、本地 Xcode 编译——本机编译产物不受 Gatekeeper 拦截，**不需要公证**。

2. 或交由其他已持有付费开发者账号的维护者，负责打包、签名 \+ 公证并发布 Release 安装包。

## 常见误区澄清

- ❌ 公证要单独交一笔扫描费 → ✅ 公证包含在开发者会员权益内，年费是入会资格费，不是公证服务费。

- ❌ 只要能代码签名就能公证 → ✅ 免费账号只能拿 Apple Development 开发证书（仅本机调试），不能拿 Developer ID，无法对外公证。

- ❌ 公证会审核业务功能 → ✅ 公证只做恶意代码扫描，不审查你预览 livp 这个功能合不合规。

# 附录：Appex 体积膨胀成因与控制清单

Appex 本质是嵌入在主 App 包内的独立 Bundle，**单独统计体积、单独签名**。它的体积坑和普通 macOS App 不一样——QuickLook 扩展运行在 quicklookd 进程中，体积越大加载越慢、内存占用越高，且公证扫描面越大。

## 体积膨胀的主要成因

|成因|说明|对本项目的影响|
|---|---|---|
|**静态链接第三方库**|`.a` 静态库编译时把全部机器码拷进 Appex 二进制；即使只用到少量函数，未开 LTO / 死代码剥离时整包塞入。|libheif\.a、libraw\.a、libpng\.a 直接打入 PreviewExtension 会暴涨数 MB。|
|**内嵌第三方 dylib**|把 `libxxx.dylib` 放进 `PreviewExtension.appex/Contents/Frameworks/`，整包计入 Appex 体积；fat 二进制（x86\_64 \+ arm64）直接翻倍。|系统 Framework 不需要打包，运行时从系统目录加载；只有外部 dylib 才会膨胀。|
|**通用二进制（fat slice）**|默认 Archive 同时打包 arm64 \+ x86\_64 两套机器码，体积接近翻倍。|若只面向 Apple Silicon，可在 Build Settings 限定 arm64，砍掉 Intel slice。|
|**未剥离调试符号**|Release 未开启 Strip，符号表留在最终二进制；dSYM 若错误嵌入二进制也会膨胀。|Build Settings：`Strip Debug Symbols During Copy = YES`，`Strip Style = All Symbols`。|
|**资源文件误入 Appex**|图片、图标、测试素材、字体、多语言 `.lproj`、残留 storyboard 被加入 Copy Bundle Resources。|务必确认资源加到了 PreviewExtension target，而不是主 App target；MVP 只保留必要本地化。|
|**未开 LTO / 死代码剥离**|关闭 LTO 和 Whole Module Optimization 后，链接器无法删除未使用的函数、类、常量。Swift 项目尤其明显。|开启 Whole Module Optimization \+ LTO \+ `-dead_strip`。|
|**Swift 运行时开销**|Swift ABI 不稳定，Swift 运行时、类型元数据、协议表会嵌入二进制；引入 SPM 包会进一步增加模块元数据。|尽量不引入 SPM 第三方包，优先系统 API。|
|**残留源文件 / 错误 target**|旧 \.swift 文件未从 Compile Sources 移除；测试 target 代码被错误合并进 Appex。|定期检查 Compile Sources 列表，移除未引用文件。|

## 快速排查命令

```bash
# 查看 Appex 主二进制大小
ls -lh LivePhotoQuickLook.app/Contents/PlugIns/PreviewExtension.appex/Contents/MacOS/

# 查看二进制包含哪些 CPU 架构
lipo -info LivePhotoQuickLook.app/Contents/PlugIns/PreviewExtension.appex/Contents/MacOS/PreviewExtension

# 递归列出 Appex 内所有文件大小，定位大文件
du -sh LivePhotoQuickLook.app/Contents/PlugIns/PreviewExtension.appex/*
du -sh LivePhotoQuickLook.app/Contents/PlugIns/PreviewExtension.appex/Contents/Resources/*

```

## 体积控制清单（MVP 落地）

* [ ] 优先链接系统 Framework / \.tbd，不静态库、不内嵌第三方 dylib

* [ ] Release 构建开启 Strip = All Symbols \+ LTO \+ Whole Module Optimization

* [ ] 按需裁剪架构：只保留 arm64（放弃 Intel），避免 fat 二进制双倍体积

* [ ] 清理 Appex 的 Copy Bundle Resources，只保留必需资源，删除测试素材与多余本地化

* [ ] 精简 SPM 依赖，尽量不引入第三方 Swift 包

* [ ] 定期用 lipo、du 检查 Appex 产物体积，定位膨胀来源

* [ ] livp 解压临时文件运行时写到系统临时目录，不打包进 Appex（当前方案已满足）

**与公证的关系：**体积膨胀 ≠ 公证失败，两者独立；但引入第三方静态库 / 内嵌 dylib 时，**一方面库会让体积暴涨，另一方面外部二进制容易触发公证扫描报错**——这就是正文把两者写在一起的原因。

# 交付形态更新（0.1.0-beta）

> 本节记录 0.1.0-beta 相对原始 MVP 设计的交付变化，原文其余内容保持不变。

## 变化摘要

- 实测环境（macOS 15.8.1）中，系统**现代类型注册表对 .livp 返回 dyn 动态类型**（系统自带 .pvt 亦如此），导致 QuickLook 预览扩展与 Spotlight 导入器无法被系统调用；该问题与代码无关（旧 CoreServices C API 解析正确，现代 UniformTypeIdentifiers 框架不一致）。
- 因此 beta 交付形态调整为：**独立浏览式 App 为主交付**（双击/⌘O/拖放打开，窗口内封面 + 左下角实况按钮播放），QuickLook 扩展（PreviewExtension）与 Spotlight 导入器（LivpImporter）两个 target **保留**——在标准环境或未来系统版本中仍可作为空格预览方案。

## 独立 App 验收清单（替代原空格预览清单）

- [ ] 双击 .livp 打开窗口，显示 HEIC 封面
- [ ] 左下角「实况」按钮可见，点击播放 MOV
- [ ] 播放完毕自动回封面，再次点击可重播
- [ ] 左侧文件列表可切换多个已打开文件
- [ ] 滚轮缩放、拖拽平移正常
- [ ] 关闭文件 / 退出 App 后播放器释放、临时目录清理

