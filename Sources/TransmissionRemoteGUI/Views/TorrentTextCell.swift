import AppKit

/// Virtualized label cell. A plain button opens a checkmark menu, avoiding NSPopUpButton's
/// duplicated current-value row while keeping text styling consistent across table selection.
final class LabelPickerCell: NSTableCellView {
    private let button = NSButton(title: "", target: nil, action: nil)
    private var labels: [String] = []
    private var choices: [String] = []
    private var onChange: ([String]) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .smallSquare
        button.alignment = .left
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        button.imagePosition = .imageRight
        button.contentTintColor = .labelColor
        button.cell?.usesSingleLineMode = true
        button.cell?.lineBreakMode = .byTruncatingTail
        button.target = self
        button.action = #selector(showMenu)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("LabelPickerCell is created programmatically") }

    func configure(labels: [String], choices: [String], fontSize: CGFloat, onChange: @escaping ([String]) -> Void) {
        self.labels = labels
        self.choices = Array(Set(choices + labels)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        self.onChange = onChange
        button.font = .systemFont(ofSize: fontSize)
        updateTitle()
    }

    private func updateTitle() {
        let title = labels.isEmpty ? "—" : labels.joined(separator: ", ")
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: button.font ?? .systemFont(ofSize: 11),
        ])
        button.toolTip = title
    }

    @objc private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for label in choices {
            let item = NSMenuItem(title: label, action: #selector(toggleLabel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = label
            item.state = labels.contains(label) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: loc("Nincs címke"), action: #selector(clearLabels), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        let create = NSMenuItem(title: loc("Új címke…"), action: #selector(createLabel), keyEquivalent: "")
        create.target = self
        menu.addItem(create)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }

    @objc private func toggleLabel(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }
        if labels.contains(label) { labels.removeAll { $0 == label } }
        else { labels.append(label) }
        updateTitle()
        onChange(labels)
    }

    @objc private func clearLabels() {
        labels.removeAll()
        updateTitle()
        onChange(labels)
    }

    @objc private func createLabel() {
        let alert = NSAlert()
        alert.messageText = loc("Új címke")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: loc("Hozzáad"))
        alert.addButton(withTitle: loc("Mégse"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let label = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        if !labels.contains(label) { labels.append(label) }
        updateTitle()
        onChange(labels)
    }
}

/// Keep a single-line label at its natural height, centered in the fixed-height row.
/// Returning the label itself would stretch its text cell to the row's full height,
/// where NSTextField's default text drawing is top-aligned.
final class TorrentTextCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label
        // NSTextField anchors refer to its inset alignment rect. Compensate so its
        // frame (and horizontal text padding) stays identical to the old full-row label.
        let insets = label.alignmentRectInsets
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("TorrentTextCell is created programmatically")
    }

    /// Preserve right-click / Ctrl-click over both the label and its vertical padding.
    /// Like ProgressCell, a container must ask the table for its row context menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        var view = superview
        while let v = view, !(v is NSTableView) { view = v.superview }
        return view?.menu(for: event)
    }
}
