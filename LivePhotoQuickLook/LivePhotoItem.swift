import Foundation

/// 一个已打开（或待打开）的 .livp 文件条目：负责按需解压与资源释放。
final class LivePhotoItem {

    let fileURL: URL
    private(set) var resource: LivpResource?
    private(set) var lastError: Error?

    var name: String { fileURL.lastPathComponent }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 解析 livp；成功返回 nil，失败返回错误。
    @discardableResult
    func load() -> Error? {
        if resource != nil { return nil }
        do {
            resource = try LivpParser.parseLivp(fileURL: fileURL)
            lastError = nil
            return nil
        } catch let parseError {
            lastError = parseError
            resource = nil
            return parseError
        }
    }

    /// 释放临时目录资源。
    func unload() {
        if let res = resource {
            LivpParser.cleanupTempDir(res.tempDir)
            resource = nil
        }
    }
}
