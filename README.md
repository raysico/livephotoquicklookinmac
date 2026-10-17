# LivePhotoQuickLook

> macOS 实况照片（.livp）预览工具：HEIC 封面 + 「实况」按钮播放 MOV，浏览式窗口可同时打开多个文件。

当前版本：0.1.0-beta（唯一真源为 package.json，随「准备发布新版」流程同步）

## 项目介绍

iPhone 导出的实况照片（.livp：zip 包内为 HEIC 封面 + MOV 视频）在 macOS 上无法直接预览。本项目提供：

- **独立浏览式 App（当前主交付）**：双击 .livp 打开窗口，左侧文件列表 + 右侧预览；左下角「实况」按钮播放视频，播完自动回封面。
- **QuickLook 预览扩展（保留）**：标准环境下可在访达按空格预览（详见「已知限制」）。

## 功能特性

- 解压 .livp（zip）→ 自动识别 HEIC/JPG 封面与 MOV 视频
- 窗口预览：封面铺满、左下角「实况」按钮播放/暂停、播完回封面、可重播
- 滚轮缩放、拖拽平移
- 浏览式多文件列表（⌘O 打开 / 拖入窗口 / 双击关联打开）
- 播放结束与退出时自动释放播放器、清理临时文件
- 损坏包 / 缺封面 / 缺视频给出明确错误提示
- 安全：解压时拒绝绝对路径与 `..` 路径穿越条目

## 环境依赖

- macOS 12+（本工程仅构建 arm64；Apple Silicon）
- Xcode 14+（本工程在 Xcode 26.3 验证）
- 系统 Framework：AppKit、AVKit / AVFoundation、ImageIO、QuickLookUI、CoreSpotlight
- 系统 `libarchive.tbd`（zip 解压；桥接头内手写 ABI 原型，**不打包任何第三方静态库**）

## 安装

```bash
# 方式一：Xcode 打开工程后 Run
open LivePhotoQuickLook.xcodeproj

# 方式二：命令行构建 Release
xcodebuild -project LivePhotoQuickLook.xcodeproj \
  -scheme LivePhotoQuickLook -configuration Release \
  -derivedDataPath ./build build

# 部署：把构建产物拷入 /Applications
cp -R build/Build/Products/Release/LivePhotoQuickLook.app /Applications/
```

首次使用建议把 LivePhotoQuickLook.app 设为 .livp 的默认打开程序（双击关联）。

## 使用方法

1. 双击任意 `.livp`（或拖到 App 图标/窗口）→ 窗口显示封面 + 「实况」按钮；
2. 点「实况」→ 播放视频；播完自动回封面；再点可重播；
3. ⌘O 继续打开其他文件，左侧列表点击切换；
4. 滚轮缩放、拖拽平移图片。

## 已知限制

- macOS 15 的现代类型注册表对 `.livp` 返回 dyn 动态类型（系统行为），QuickLook 扩展与 Spotlight 导入器可能不被系统调用；独立 App 不受影响（双击关联需显式设置默认打开程序）。
- LivpImporter（Spotlight 导入器）要求 macOS 13+。
- 工程内调试日志已在 0.1.0-beta 清理；`QT`/`AVPlayer` 播放声音默认开启。

## 作者

- hoxiudimdim（raysico@gmail.com）

## 贡献者

- 欢迎提交 Issue 与 Pull Request。
- 贡献者名单：hoxiudimdim

## 许可证

见 [LICENSE.md](LICENSE.md)
