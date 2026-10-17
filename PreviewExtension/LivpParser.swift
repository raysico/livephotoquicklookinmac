import Foundation

enum LivpParseError: Error {
    case openFailed
    case noCoverFound
    case noVideoFound
    case readEntryFailed
}

struct LivpResource {
    let coverURL: URL
    let videoURL: URL
    let tempDir: URL
}

// libarchive 返回码（archived.h 定义：ARCHIVE_OK = 0，ARCHIVE_EOF = 1）
private let kArchiveOK: Int32 = 0
private let kArchiveEOF: Int32 = 1
// mode_t 中 S_IFMT 掩码后的常规文件位（0100000 = 32768）
private let kRegularFileType: UInt16 = 0o100000

/// livp（zip 归档）解压模块：遍历内部条目，按扩展名识别 HEIC/JPG 封面与 MOV 视频，
/// 写入独立 UUID 临时目录（并发预览实例互不干扰），用完调用 cleanupTempDir 清理。
final class LivpParser {

    static func parseLivp(fileURL: URL) throws -> LivpResource {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("livp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let archive = archive_read_new() else {
            throw LivpParseError.openFailed
        }
        archive_read_support_format_zip(archive)
        archive_read_support_filter_all(archive)
        defer { archive_read_free(archive) }

        guard archive_read_open_filename(archive, fileURL.path, 10240) == kArchiveOK else {
            throw LivpParseError.openFailed
        }

        var coverURL: URL?
        var videoURL: URL?
        var entry: UnsafeMutableRawPointer?

        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == kArchiveEOF { break }
            guard status == kArchiveOK, let entry = entry else {
                throw LivpParseError.readEntryFailed
            }

            // 只处理常规文件条目；目录条目无需落盘
            guard archive_entry_filetype(entry) == kRegularFileType,
                  let nameCString = archive_entry_pathname(entry) else {
                continue
            }
            let entryName = String(cString: nameCString)

            // C4 修正：清洗条目路径，拒绝绝对路径与 "."/".." 组件，防止逃逸临时目录
            guard let outputURL = sanitizedEntryURL(entryName: entryName, rootDir: tempDir) else {
                continue
            }

            let parentDir = outputURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            guard let fp = fopen(outputURL.path, "wb") else { continue }
            defer { fclose(fp) }

            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let bytesRead = archive_read_data(archive, &buffer, buffer.count)
                if bytesRead < 0 { throw LivpParseError.readEntryFailed }
                if bytesRead == 0 { break }
                buffer.withUnsafeBytes { raw in
                    _ = fwrite(raw.baseAddress, 1, Int(bytesRead), fp)
                }
            }
            fflush(fp)

            // livp 内部文件名不固定：必须按后缀遍历识别，不能硬编码 image.heic
            let ext = (entryName as NSString).pathExtension.lowercased()
            if ext == "heic" || ext == "jpg" || ext == "jpeg" {
                if coverURL == nil { coverURL = outputURL }
            } else if ext == "mov" {
                if videoURL == nil { videoURL = outputURL }
            }
        }

        // C3 修正：封面与视频缺失分别报错，语义准确
        guard let cover = coverURL else { throw LivpParseError.noCoverFound }
        guard let video = videoURL else { throw LivpParseError.noVideoFound }
        return LivpResource(coverURL: cover, videoURL: video, tempDir: tempDir)
    }

    static func cleanupTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private static func sanitizedEntryURL(entryName: String, rootDir: URL) -> URL? {
        let nsName = entryName as NSString
        if nsName.isAbsolutePath { return nil }
        let components = nsName.pathComponents
        guard !components.isEmpty else { return nil }
        for component in components where component == ".." || component == "." {
            return nil
        }
        return components.reduce(rootDir) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    }
}
