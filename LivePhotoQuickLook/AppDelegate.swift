import AppKit

/// 主壳 App（浏览式）：单窗口 = 左侧文件列表 + 右侧预览内容。
/// 双击 .livp / ⌘O / 拖文件到窗口或 Dock 图标都能打开。
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private let splitVC = NSSplitViewController()
    private let sidebar = SidebarViewController()
    private let content = ContentViewController()
    private var items: [LivePhotoItem] = []
    /// openFiles 可能在 didFinishLaunching 之前到达，先入队延迟处理
    private var pendingOpenURLs: [URL] = []

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        flushPendingOpenURLs()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        content.teardown()
        items.forEach { $0.unload() }
    }

    /// Finder 双击 .livp / Dock 拖文件触发
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        pendingOpenURLs.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
        if window != nil {
            flushPendingOpenURLs()
        }
        sender.reply(toOpenOrPrint: .success)
    }

    private func flushPendingOpenURLs() {
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        for url in urls {
            addItem(url)
        }
        sidebar.reload()
        if let last = urls.last {
            selectItem(withURL: last)
        }
        showWindow()
    }

    // MARK: - 窗口

    private func buildWindow() {
        guard window == nil else { return }

        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(NSSplitViewItem(viewController: content))

        let newWindow = NSWindow(contentViewController: splitVC)
        newWindow.title = "LivePhotoQuickLook"
        newWindow.setContentSize(NSSize(width: 980, height: 640))
        newWindow.minSize = NSSize(width: 560, height: 400)
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow

        sidebar.onSelect = { [weak self] item in
            self?.content.show(item)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWindow() {
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 菜单

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 LivePhotoQuickLook",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 LivePhotoQuickLook",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "打开…",
                         action: #selector(openDocument(_:)),
                         keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openDocument(_ sender: Any?) {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "选择 .livp 实况照片"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.addItem(url)
            }
            self?.sidebar.reload()
            if let last = panel.urls.last {
                self?.selectItem(withURL: last)
            }
        }
    }

    // MARK: - 文件条目管理

    private func addItem(_ url: URL) {
        if items.contains(where: { $0.fileURL == url }) {
            return
        }
        items.append(LivePhotoItem(fileURL: url))
        sidebar.items = items
    }

    private func selectItem(withURL url: URL) {
        guard let index = items.firstIndex(where: { $0.fileURL == url }) else { return }
        sidebar.selectRow(index)
        content.show(items[index])
    }
}
