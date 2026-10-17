#ifndef PreviewExtension_Bridging_Header_h
#define PreviewExtension_Bridging_Header_h

// C1 修正：libarchive 是 C 库，Swift 无法 `import libarchive`；
// 且 macOS SDK 不提供 archive.h / archive_entry.h 头文件。
// 此处按 libarchive 3.x 公开 ABI 手写最小原型（用 void * 避免
// 不完整结构体 typedef 的 Swift 导入问题），链接系统 libarchive.tbd
// （dylib 位于 dyld 共享缓存，运行时可用，已实测验证）。

#include <stddef.h>
#include <stdint.h>

void *archive_read_new(void);
int archive_read_support_format_zip(void *);
int archive_read_support_filter_all(void *);
int archive_read_open_filename(void *, const char *, size_t);
int archive_read_next_header(void *, void **);
int64_t archive_read_data(void *, void *, size_t);
int archive_read_free(void *);
const char *archive_entry_pathname(void *);
unsigned short archive_entry_filetype(void *);

#endif /* PreviewExtension_Bridging_Header_h */
