import AppKit

/// 左侧文件列表：展示已打开的 .livp 条目，选中时通知内容区切换。
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    var items: [LivePhotoItem] = []
    var onSelect: ((LivePhotoItem?) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "文件"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        view = scrollView
    }

    func reload() {
        tableView.reloadData()
    }

    func selectRow(_ row: Int) {
        guard row >= 0 && row < items.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = items[row].name
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        onSelect?(row >= 0 && row < items.count ? items[row] : nil)
    }
}
