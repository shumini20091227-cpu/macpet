import AppKit

@MainActor
final class ExpressionDeletionPicker: NSView {
    private let entries: [PetExpressions.Entry]
    private var checkboxes: [NSButton] = []
    private let countLabel = NSTextField(labelWithString: "已选 0 项")
    weak var deleteButton: NSButton?

    var selectedEntries: [PetExpressions.Entry] {
        zip(entries, checkboxes).compactMap { $0.1.state == .on ? $0.0 : nil }
    }

    init(entries: [PetExpressions.Entry]) {
        self.entries = entries
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 330))
        let all = NSButton(title: "全选", target: self, action: #selector(selectEveryExpression))
        all.frame = NSRect(x: 0, y: 298, width: 70, height: 28)
        addSubview(all)
        let clear = NSButton(title: "取消全选", target: self, action: #selector(clearSelection))
        clear.frame = NSRect(x: 76, y: 298, width: 90, height: 28)
        addSubview(clear)
        countLabel.frame = NSRect(x: 270, y: 302, width: 145, height: 20)
        countLabel.alignment = .right
        addSubview(countLabel)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 290))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        for entry in entries {
            let checkbox = NSButton(checkboxWithTitle: entry.name, target: self, action: #selector(selectionChanged))
            checkbox.lineBreakMode = .byTruncatingMiddle
            checkbox.toolTip = entry.name
            checkbox.widthAnchor.constraint(equalToConstant: 380).isActive = true
            checkboxes.append(checkbox)
            stack.addArrangedSubview(checkbox)
        }
        scroll.documentView = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        addSubview(scroll)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func selectEveryExpression() {
        checkboxes.forEach { $0.state = .on }
        selectionChanged()
    }

    @objc private func clearSelection() {
        checkboxes.forEach { $0.state = .off }
        selectionChanged()
    }

    @objc private func selectionChanged() {
        let count = selectedEntries.count
        countLabel.stringValue = "已选 \(count) 项"
        deleteButton?.title = count == 0 ? "删除所选" : "删除所选（\(count)）"
        deleteButton?.isEnabled = count > 0
    }
}
