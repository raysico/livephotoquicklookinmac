import CoreSpotlight
import UniformTypeIdentifiers
import Foundation

/// 现代 Spotlight 导入器（com.apple.spotlight.import 扩展点）：
/// 明确告诉 mds，.livp 文件的内容类型是 com.hoxiudimdim.livp，
/// 使 Finder 图标、Spotlight 搜索与 QuickLook 扩展匹配都能拿到正确类型。
/// CSImportExtension 要求 macOS 13+；旧系统（12）上该导入器不加载，
/// 仅影响 Spotlight 元数据类型，不影响 App 本体运行。
final class LivpImporter: CSImportExtension {

    override func update(_ attributeSet: CSSearchableItemAttributeSet,
                         forFileAt fileURL: URL) throws {
        attributeSet.contentType = "com.hoxiudimdim.livp"
        attributeSet.displayName = fileURL.deletingPathExtension().lastPathComponent
    }
}
