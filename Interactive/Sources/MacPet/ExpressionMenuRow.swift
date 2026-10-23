import AppKit

/// Separate buttons keep removal from also selecting the expression.
@MainActor
final class ExpressionMenuRow: NSView {
    private let onSelect: () -> Void
    private let onRemove: () -> Void

    init(title: String, selected: Bool, canRemove: Bool,
         onSelect: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onRemove = onRemove
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        autoresizingMask = [.width]

        let select = NSButton(title: (selected ? "✓  " : "    ") + title,
                              target: self, action: #selector(choose))
        select.isBordered = false
        select.alignment = .left
        select.font = .menuFont(ofSize: 13)
        select.lineBreakMode = .byTruncatingTail
        select.frame = NSRect(x: 10, y: 2, width: canRemove ? 208 : 240, height: 26)
        select.autoresizingMask = [.width]
        select.setAccessibilityLabel("切换到「\(title)」" + (selected ? "，当前表情" : ""))
        addSubview(select)

        if canRemove {
            let remove = NSButton(title: "×", target: self, action: #selector(removeExpression))
            remove.isBordered = false
            remove.font = .systemFont(ofSize: 19)
            remove.contentTintColor = .secondaryLabelColor
            remove.frame = NSRect(x: 224, y: 2, width: 28, height: 26)
            remove.autoresizingMask = [.minXMargin]
            remove.toolTip = "移除「\(title)」"
            remove.setAccessibilityLabel("移除「\(title)」")
            addSubview(remove)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func choose() { onSelect() }
    @objc private func removeExpression() { onRemove() }
}
