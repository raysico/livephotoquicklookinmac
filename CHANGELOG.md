# CHANGELOG

## 0.1.0-beta（2026-10-17）

### feat

- **独立浏览式 App**：主壳从空壳宿主升级为完整应用 —— 左侧文件列表 + 右侧预览窗口；支持 ⌘O 打开、拖放、双击关联、多文件切换，退出时释放播放器与临时文件。
- **QuickLook 预览扩展（PreviewExtension.appex）**：`.livp` 空格预览，HEIC 封面 + 左下角「实况」按钮播放 MOV，播完回封面（保留，供标准环境使用）。
- **Spotlight 导入器（LivpImporter.appex）**：将 `.livp` 标记为 `com.hoxiudimdim.livp`（需 macOS 13+）。
- **LivpParser**：基于系统 libarchive 解压 zip，按后缀识别封面/视频，路径穿越防护，临时目录清理。
- 单元测试：LivpParser 7/7（正常包、损坏包、无媒体、有封面缺视频、路径穿越、jpg 封面变体、临时目录清理）。

### fix

- `QLSupportedContentTypes` 移入 `NSExtensionAttributes`（原顶层写法导致扩展不匹配任何类型）。
- UTI 声明改为 `UTExportedTypeDeclarations`，主 App 与 Appex 双声明 `.livp` 映射。
- 生命周期：`openFiles` 先于 `didFinishLaunching` 到达时先入队（修复带文件启动崩溃）。
- 双击关联：使用 `NSWorkspace.setDefaultApplication` 显式绑定（绕过 macOS 15 现代类型注册表对 `.livp` 返回 dyn 的问题）。

### chore

- 工程：手写 pbxproj（app + PreviewExtension + LivpImporter 三个 target，arm64，macOS 12+）。
- 版本：package.json `0.0.0` → `0.1.0-beta`；MARKETING_VERSION 同步。
- 清理：移除扩展内 `[LPQL]` 调试日志。

### 关联提交

| 提交 | 说明 |
|---|---|
| `c707402` | chore: init project base v0.0.0 |
| `21cccfa` | feat: 实现 livp QuickLook 预览扩展 MVP |
| `da1ad3e` | feat: 新增现代 Spotlight 导入器 LivpImporter |
| `ab6f91d` | feat: 主壳升级为浏览式独立 App |

### git tag

- `v0.1.0-beta`（随「发布新版本」流程创建）
