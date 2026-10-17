# TECH

## 1. 架构总览

```
LivePhotoQuickLook（独立 App，主交付）
├── AppDelegate            // 窗口/菜单/⌘O/拖放/openFiles 生命周期
├── SidebarViewController  // 左侧文件列表（NSTableView）
├── ContentViewController  // 右侧预览：滚动视图 + NSImageView + AVPlayerView + 实况按钮
├── LivePhotoItem          // 文件模型：解压缓存、错误状态、临时目录释放
├── LivpParser             // zip 解压 + 条目识别（同时被 App 与扩展复用）
└── Contents/PlugIns/
    ├── PreviewExtension.appex   // QuickLook 预览扩展（保留）
    └── LivpImporter.appex       // 现代 Spotlight 导入器（保留，macOS 13+）
```

- 构建：Xcode 工程（手写 pbxproj，objectVersion 56），目标 macOS 12+，仅 arm64。
- 签名：Apple Development（本地）；Release 构建后可手动剔除 get-task-allow 再签名。
- 系统依赖：AppKit / AVKit / AVFoundation / ImageIO / QuickLookUI / CoreSpotlight + 系统 `libarchive.tbd`。

## 2. 数据流

```
用户双击/⌘O/拖入 .livp
  → AppDelegate 收集 URL
  → LivePhotoItem.load()
      → LivpParser.parseLivp(fileURL:)
          展开 zip（libarchive）→ 按后缀识别 HEIC/JPG（封面）与 MOV（视频）
          → 写入 NSTemporaryDirectory()/livp-<UUID>/（沙盒容器内）
      → 返回 LivpResource(coverURL, videoURL, tempDir)
  → ContentViewController.show(item)
      → NSImage(contentsOf: coverURL) → 滚动视图展示（可缩放平移）
      → AVPlayer(url: videoURL) → 点击「实况」播放；播完回封面
  → 切换文件 / 退出：移除观察者、释放 AVPlayer、清理临时目录
```

## 3. 模块与职责

| 模块 | 职责 | 关键点 |
|---|---|---|
| `LivpParser` | zip 解压、条目识别、路径清洗 | 拒绝绝对路径与 `..`；每实例独立 UUID 临时目录（并发安全） |
| `LivePhotoItem` | 单文件状态 | 惰性解析；`unload()` 清理临时目录 |
| `ContentViewController` | 预览与播放 | 观察者生命周期、`reset()` 释放、缩放适配 |
| `SidebarViewController` | 文件列表 | 选中回调驱动内容区切换 |
| `AppDelegate` | 应用生命周期 | `openFiles` 早于 `didFinishLaunching`（先入队）；`applicationWillTerminate` 清理 |
| `PreviewExtension` | QuickLook 预览 | 控制器类名须匹配 `NSExtensionPrincipalClass` |
| `LivpImporter` | Spotlight 类型标记 | `com.apple.spotlight.import` + `CSSupportedContentTypes` |

## 4. 关键决策与约束（选型记录）

- **libarchive 而非第三方库**：链接系统 `libarchive.tbd`；SDK 不提供头文件，桥接头手写最小 ABI 原型（`void*` 形式）；dylib 位于 dyld 共享缓存。
- **QuickLook 扩展的 plist 结构**：`QLSupportedContentTypes` 必须放在 `NSExtensionAttributes` 内（顶层写法导致不匹配）。
- **UTI**：`com.hoxiudimdim.livp` 以 `UTExportedTypeDeclarations` 声明，主 App 与 Appex 双声明，tag `.livp`。
- **macOS 15 类型注册双轨制（关键环境约束）**：现代 `UniformTypeIdentifiers` 对 `.livp` 返回 `dyn.ah62d4rv4ge8024p0sa`（系统 `.pvt` 同样），旧 `CoreServices` C API 返回正确 UTI。QuickLook / Spotlight / 双击关联均走现代注册表 → 本机扩展无法被调用；双击关联通过 `NSWorkspace.setDefaultApplication(at:toOpenFileAt:)` 绑定动态类型解决。
- **生命周期**：`application(_:openFiles:)` 可能先于 `applicationDidFinishLaunching` 触发，窗口未创建时必须入队延时处理。
- **沙盒**：App 使用 App Sandbox + `files.user-selected.read-only`；解压产物写容器临时目录；扩展沙盒仅 `app-sandbox`。

## 5. 接口 / 数据模型

- 输入：`.livp` 文件（zip 归档，扩展名不固定，条目名不固定）。
- 解析产物：`LivpResource { coverURL, videoURL, tempDir }`；错误：`openFailed / noCoverFound / noVideoFound / readEntryFailed`。
- UTI：`com.hoxiudimdim.livp`（conforms to `public.data`），扩展 `.livp`。
- 版本真源：`package.json`（`0.1.0-beta`）；Xcode `MARKETING_VERSION` 同步。

## 6. 构建、部署与测试

```bash
# 构建（Release）
xcodebuild -project LivePhotoQuickLook.xcodeproj -scheme LivePhotoQuickLook \
  -configuration Release -derivedDataPath ./build build

# 单元测试（LivpParser，7 用例）
xcrun swiftc -target arm64-apple-macos12.0 \
  -import-objc-header PreviewExtension/PreviewExtension-Bridging-Header.h \
  -module-cache-path build/testcache -o build/livpparsertest \
  PreviewExtension/LivpParser.swift test/harness/main.swift -larchive
./build/livpparsertest test/data/*.livp
```

- 测试数据位于 `test/`（仅本地，不入库）。
- 验收：见 DESIGN.md「独立 App 验收清单」。

## 7. 已知问题

- 本机（macOS 15.8.1）QuickLook 扩展与 Spotlight 导入器不被系统调用（现代类型注册表返回 dyn），独立 App 不受影响。
- `CFBundleShortVersionString` 携带 `-beta` 后缀仅为本地开发便利；App Store / 公证前应改为纯数字版本。
- 双击关联依赖显式默认程序绑定（本机已设置）。
