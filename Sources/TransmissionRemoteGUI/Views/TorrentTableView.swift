import SwiftUI
import AppKit
import TransmissionKit

/// Native `NSTableView`-based torrent list. SwiftUI's `Table` does not perform
/// acceptably above ~500 rows; `NSTableView` virtualizes and handles tens of
/// thousands of rows smoothly. Sorting goes through the model's `sortOrder` (fast,
/// typed `TorrentSort`); selection is kept in two-way sync with `selection`.
struct TorrentTableView: NSViewRepresentable {
    var torrents: [Torrent]
    @Binding var selection: Set<Int>
    @Binding var sortOrder: [KeyPathComparator<Torrent>]
    var scale: Double = 1.0
    var effective: AppLanguage = .hungarian   // for tracking language changes (column header refresh)
    /// Invoked when a context-menu command is chosen. The targeted torrents are captured
    /// when the menu opens, so the command never depends on the selection binding having
    /// propagated back to SwiftUI in the meantime.
    var onCommand: (TorrentRowCommand, [Torrent]) -> Void = { _, _ in }

    private static let baseRowHeight: CGFloat = 22
    private static let baseFontSize: CGFloat = 12

    // MARK: Column specs

    struct ColumnSpec {
        let id: String
        let title: String
        /// Title in the header's column menu, when the header itself is too terse (↓ / ↑).
        let menuTitle: String
        let width: CGFloat
        let minWidth: CGFloat
        let alignment: NSTextAlignment
        let monospaced: Bool
        let isProgress: Bool
        /// Shown on first launch / after "Default Columns"; the rest are opt-in via the header menu.
        let defaultVisible: Bool
        let text: (Torrent) -> String
        let color: (Torrent) -> NSColor?
        let makeComparator: (_ ascending: Bool) -> KeyPathComparator<Torrent>

        init(id: String, title: String, menuTitle: String? = nil, width: CGFloat, minWidth: CGFloat = 40,
             alignment: NSTextAlignment = .left, monospaced: Bool = false, isProgress: Bool = false,
             defaultVisible: Bool = true,
             text: @escaping (Torrent) -> String = { _ in "" },
             color: @escaping (Torrent) -> NSColor? = { _ in nil },
             comparator: @escaping (_ ascending: Bool) -> KeyPathComparator<Torrent>) {
            self.id = id; self.title = title; self.menuTitle = menuTitle ?? title; self.width = width; self.minWidth = minWidth
            self.alignment = alignment; self.monospaced = monospaced; self.isProgress = isProgress
            self.defaultVisible = defaultVisible
            self.text = text; self.color = color; self.makeComparator = comparator
        }
    }

    static let columns: [ColumnSpec] = [
        ColumnSpec(id: "name", title: "Név", width: 320, minWidth: 160,
                   text: { $0.displayName },
                   color: { $0.hasError ? .systemRed : nil },
                   comparator: { KeyPathComparator(\Torrent.displayName, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "status", title: "Állapot", width: 120, minWidth: 80,
                   text: { $0.statusText },
                   color: { $0.hasError ? .systemRed : .secondaryLabelColor },
                   comparator: { KeyPathComparator(\Torrent.statusSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "progress", title: "Kész", width: 64, minWidth: 50, isProgress: true,
                   comparator: { KeyPathComparator(\Torrent.progress, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "size", title: "Méret", width: 78, alignment: .right, monospaced: true,
                   text: { Format.size($0.sizeSortKey) },
                   comparator: { KeyPathComparator(\Torrent.sizeSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "down", title: "↓", menuTitle: "Letöltési sebesség", width: 78, alignment: .right, monospaced: true,
                   text: { Format.rate($0.downloadRate) },
                   color: { _ in .systemGreen },
                   comparator: { KeyPathComparator(\Torrent.downloadRate, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "up", title: "↑", menuTitle: "Feltöltési sebesség", width: 78, alignment: .right, monospaced: true,
                   text: { Format.rate($0.uploadRate) },
                   color: { _ in .systemBlue },
                   comparator: { KeyPathComparator(\Torrent.uploadRate, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "eta", title: "ETA", width: 72, alignment: .right, monospaced: true,
                   text: { Format.eta($0.eta ?? -1) },
                   comparator: { KeyPathComparator(\Torrent.etaSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "ratio", title: "Arány", width: 56, alignment: .right, monospaced: true,
                   text: { Format.ratio($0.ratio) },
                   comparator: { KeyPathComparator(\Torrent.ratio, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "peers", title: "Peerek", width: 58, alignment: .right, monospaced: true,
                   text: { "\($0.sendingPeers)/\($0.connectedPeers)" },
                   comparator: { KeyPathComparator(\Torrent.connectedPeers, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "added", title: "Hozzáadva", width: 130, minWidth: 90, monospaced: true,
                   text: { $0.addedDateValue.map(dateFormatter.string(from:)) ?? "—" },
                   color: { _ in .secondaryLabelColor },
                   comparator: { KeyPathComparator(\Torrent.addedDateSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "activity", title: "Utolsó aktivitás", width: 120, minWidth: 80, monospaced: true,
                   text: { $0.activityDateValue.map(dateFormatter.string(from:)) ?? "—" },
                   color: { _ in .secondaryLabelColor },
                   comparator: { KeyPathComparator(\Torrent.activityDateSortKey, order: $0 ? .forward : .reverse) }),
        // Optional columns — hidden until enabled from the header's right-click menu.
        ColumnSpec(id: "done", title: "Befejezve", width: 130, minWidth: 90, monospaced: true, defaultVisible: false,
                   text: { $0.doneDateValue.map(dateFormatter.string(from:)) ?? "—" },
                   color: { _ in .secondaryLabelColor },
                   comparator: { KeyPathComparator(\Torrent.doneDateSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "remaining", title: "Hátralévő", width: 78, alignment: .right, monospaced: true, defaultVisible: false,
                   text: { Format.size($0.remainingSortKey) },
                   comparator: { KeyPathComparator(\Torrent.remainingSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "downloaded", title: "Letöltve", width: 78, alignment: .right, monospaced: true, defaultVisible: false,
                   text: { Format.size($0.downloadedSortKey) },
                   comparator: { KeyPathComparator(\Torrent.downloadedSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "uploaded", title: "Feltöltve", width: 78, alignment: .right, monospaced: true, defaultVisible: false,
                   text: { Format.size($0.uploadedSortKey) },
                   comparator: { KeyPathComparator(\Torrent.uploadedSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "folder", title: "Letöltési mappa", width: 180, minWidth: 80, defaultVisible: false,
                   text: { $0.folderText },
                   color: { _ in .secondaryLabelColor },
                   comparator: { KeyPathComparator(\Torrent.folderText, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "seeds", title: "Seedek", width: 76, alignment: .right, monospaced: true, defaultVisible: false,
                   text: { $0.seedsText },
                   comparator: { KeyPathComparator(\Torrent.seedsSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "leechers", title: "Leecherek", width: 76, alignment: .right, monospaced: true, defaultVisible: false,
                   text: { $0.leechersText },
                   comparator: { KeyPathComparator(\Torrent.leechersSortKey, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "tracker", title: "Tracker", width: 150, minWidth: 70, defaultVisible: false,
                   text: { $0.trackerText },
                   color: { _ in .secondaryLabelColor },
                   comparator: { KeyPathComparator(\Torrent.trackerText, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "labels", title: "Címkék", width: 120, minWidth: 60, defaultVisible: false,
                   text: { $0.labelsText },
                   color: { _ in .secondaryLabelColor },
                   comparator: { KeyPathComparator(\Torrent.labelsText, order: $0 ? .forward : .reverse) }),
    ]

    /// UserDefaults autosave name: AppKit persists column order, widths and visibility under it.
    static let columnAutosaveName = "TorrentTable"

    static let columnsByID: [String: ColumnSpec] = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    // MARK: NSViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = RowMenuTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.rowHeight = (Self.baseRowHeight * scale).rounded()  // FIXED height → fast virtualization
        // Name column absorbs width changes, so the table follows the detail panel's
        // resize (grows/shrinks) instead of forcing a horizontal scroll.
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.usesAutomaticRowHeights = false

        for spec in Self.columns {
            let col = NSTableColumn(identifier: .init(spec.id))
            col.title = loc(spec.title)
            col.width = spec.width
            col.minWidth = spec.minWidth
            col.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: true)
            col.isHidden = !spec.defaultVisible
            table.addTableColumn(col)
        }
        // Set AFTER the columns exist: this restores the user's saved order/widths/visibility.
        table.autosaveName = Self.columnAutosaveName
        table.autosaveTableColumns = true

        // Right-click on the header: choose the visible columns (like Finder / Transmission).
        let headerMenu = NSMenu()
        headerMenu.autoenablesItems = false   // keeps the always-shown name column disabled
        headerMenu.delegate = context.coordinator
        table.headerView?.menu = headerMenu

        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked)
        // Right-click / Ctrl-click: the table asks the coordinator for a menu for the clicked row.
        // The placeholder `menu` is never shown (the override always supplies the real one);
        // it only guarantees AppKit takes the contextual-menu path at all.
        table.menu = NSMenu()
        table.menuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.menu(forClickedRow: row)
        }

        // Initial sort indicator on the header (the model's default: added date descending).
        table.sortDescriptors = [NSSortDescriptor(key: "added", ascending: false)]

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true

        context.coordinator.tableView = table
        context.coordinator.data = torrents
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(torrents: torrents, selection: selection, scale: scale)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: TorrentTableView
        weak var tableView: NSTableView?
        var data: [Torrent] = []
        private var isSyncingSelection = false
        private var lastScale: Double = 1.0
        private var lastLanguage: AppLanguage?

        /// Torrents the currently open context menu acts on (captured when it opens).
        private var menuTargets: [Torrent] = []
        private lazy var rowMenu: NSMenu = Self.makeRowMenu(target: self)

        init(_ parent: TorrentTableView) { self.parent = parent }

        // MARK: Context menu

        /// The menu for a right-clicked row, or `nil` on empty space (where macOS shows none).
        func menu(forClickedRow row: Int) -> NSMenu? {
            guard let tv = tableView else { return nil }
            let rows = TorrentRowMenu.targetRows(clicked: row, selection: tv.selectedRowIndexes)
            guard !rows.isEmpty else { return nil }

            // Clicking outside the selection retargets it, exactly like Finder.
            if rows != tv.selectedRowIndexes {
                tv.selectRowIndexes(rows, byExtendingSelection: false)   // also syncs the SwiftUI binding
            }

            menuTargets = TorrentRowMenu.targets(rows: rows, in: data)
            guard !menuTargets.isEmpty else { return nil }

            // Titles are refreshed on every open so a language switch is picked up for free.
            for item in rowMenu.items {
                guard let command = item.representedObject as? TorrentRowCommand,
                      let entry = TorrentRowMenu.layout.first(where: { $0.command == command })
                else { continue }
                item.title = loc(entry.titleKey)
                item.isEnabled = TorrentRowMenu.isEnabled(command, for: menuTargets)
            }
            return rowMenu
        }

        @objc func menuCommandSelected(_ sender: NSMenuItem) {
            guard let command = sender.representedObject as? TorrentRowCommand else { return }
            parent.onCommand(command, menuTargets)
        }

        /// Builds the menu from `TorrentRowMenu.layout`, so a command can never be
        /// added to the enum and silently left out of the menu.
        private static func makeRowMenu(target: Coordinator) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false   // enablement comes from TorrentRowMenu.isEnabled
            for entry in TorrentRowMenu.layout {
                let item = NSMenuItem(title: loc(entry.titleKey),
                                      action: #selector(Coordinator.menuCommandSelected(_:)),
                                      keyEquivalent: "")
                item.target = target
                item.representedObject = entry.command
                menu.addItem(item)
                if entry.separatorAfter { menu.addItem(.separator()) }
            }
            return menu
        }

        func update(torrents: [Torrent], selection: Set<Int>, scale: Double) {
            var reload = false
            if scale != lastScale {
                lastScale = scale
                tableView?.rowHeight = (TorrentTableView.baseRowHeight * scale).rounded()
                reload = true
            }
            if parent.effective != lastLanguage {
                lastLanguage = parent.effective
                refreshColumnTitles()
                reload = true
            }
            if torrents != data {
                data = torrents
                reload = true
            }
            if reload { tableView?.reloadData() }
            syncSelection(selection)
        }

        /// Re-titles the column headers for the current language (called on language change).
        private func refreshColumnTitles() {
            guard let tv = tableView else { return }
            for col in tv.tableColumns {
                if let spec = TorrentTableView.columnsByID[col.identifier.rawValue] {
                    col.title = loc(spec.title)
                }
            }
        }

        // MARK: Header menu — column visibility

        /// Rebuilt on every open, so titles follow the language and checkmarks the current state.
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tv = tableView else { return }
            for col in tv.tableColumns {
                guard let spec = TorrentTableView.columnsByID[col.identifier.rawValue] else { continue }
                let item = NSMenuItem(title: loc(spec.menuTitle), action: #selector(toggleColumn(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = spec.id
                item.state = col.isHidden ? .off : .on
                item.isEnabled = spec.id != "name"   // the name column is always shown
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let reset = NSMenuItem(title: loc("Alapértelmezett oszlopok"), action: #selector(resetColumns), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }

        @objc func toggleColumn(_ sender: NSMenuItem) {
            guard let tv = tableView, let id = sender.representedObject as? String, id != "name",
                  let col = tv.tableColumn(withIdentifier: .init(id)) else { return }
            col.isHidden.toggle()
            if !col.isHidden { makeRoom(for: col, in: tv) }
        }

        /// Restores the original column set, order and widths.
        @objc func resetColumns() {
            guard let tv = tableView else { return }
            for (index, spec) in TorrentTableView.columns.enumerated() {
                guard let from = tv.tableColumns.firstIndex(where: { $0.identifier.rawValue == spec.id }) else { continue }
                if from != index { tv.moveColumn(from, toColumn: index) }
                let col = tv.tableColumns[index]
                col.isHidden = !spec.defaultVisible
                col.width = spec.width
            }
            if let name = tv.tableColumn(withIdentifier: .init("name")) { makeRoom(for: nil, in: tv, name: name) }
        }

        /// Only the name column autoresizes, so a newly shown column would push the table into a
        /// horizontal scroll. Shrink the name column (down to its minimum) to fit it instead.
        private func makeRoom(for column: NSTableColumn?, in tv: NSTableView,
                              name: NSTableColumn? = nil) {
            guard let name = name ?? tv.tableColumn(withIdentifier: .init("name")),
                  let clip = tv.enclosingScrollView?.contentView else { return }
            let spacing = tv.intercellSpacing.width
            let used = tv.tableColumns.filter { !$0.isHidden }.reduce(0) { $0 + $1.width + spacing }
            let overflow = used - clip.bounds.width
            if overflow > 0 {
                name.width = max(name.minWidth, name.width - overflow)
            } else if column == nil {
                name.width += -overflow   // after a reset: let the name column take the free space
            }
        }

        private func syncSelection(_ selection: Set<Int>) {
            guard let tv = tableView else { return }
            let target = IndexSet(data.indices.filter { selection.contains(data[$0].id) })
            if target != tv.selectedRowIndexes {
                isSyncingSelection = true
                tv.selectRowIndexes(target, byExtendingSelection: false)
                isSyncingSelection = false
            }
        }

        // MARK: DataSource

        func numberOfRows(in tableView: NSTableView) -> Int { data.count }

        // MARK: Delegate — cells

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let spec = TorrentTableView.columnsByID[tableColumn.identifier.rawValue],
                  row < data.count else { return nil }
            let t = data[row]

            let fontSize = TorrentTableView.baseFontSize * parent.scale

            if spec.isProgress {
                let id = NSUserInterfaceItemIdentifier("progressCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? ProgressCell) ?? {
                    let c = ProgressCell(); c.identifier = id; return c
                }()
                cell.configure(value: t.progress, error: t.hasError, scale: parent.scale)
                return cell
            } else {
                let id = NSUserInterfaceItemIdentifier("textCell")
                let field = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? {
                    let f = NSTextField(labelWithString: "")
                    f.identifier = id
                    f.lineBreakMode = .byTruncatingTail
                    f.cell?.usesSingleLineMode = true
                    return f
                }()
                field.font = spec.monospaced
                    ? .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
                    : .systemFont(ofSize: fontSize)
                field.stringValue = spec.id == "status" ? locStatus(spec.text(t)) : spec.text(t)
                field.alignment = spec.alignment
                field.textColor = spec.color(t) ?? .labelColor
                field.toolTip = spec.id == "name" && t.hasError ? t.errorString : nil
                return field
            }
        }

        // MARK: Delegate — sorting

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let desc = tableView.sortDescriptors.first, let key = desc.key,
                  let spec = TorrentTableView.columnsByID[key] else { return }
            parent.sortOrder = [spec.makeComparator(desc.ascending)]
        }

        // MARK: Delegate — selection

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let tv = tableView else { return }
            let ids = tv.selectedRowIndexes.compactMap { $0 < data.count ? data[$0].id : nil }
            parent.selection = Set(ids)
        }

        @objc func doubleClicked() {
            // Double-click updates the detail view via the selection; there is no separate action.
        }
    }
}

/// `NSTableView` that routes right-click / Ctrl-click to a provider which knows the row
/// under the cursor. Without this the table has no `menu` at all and the click does nothing.
final class RowMenuTableView: NSTableView {
    /// Returns the menu for the clicked row index (`-1` when the click missed every row).
    var menuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        _ = super.menu(for: event)   // let NSTableView set clickedRow/clickedColumn first
        let point = convert(event.locationInWindow, from: nil)
        return menuProvider?(row(at: point))
    }
}

/// Custom-drawn progress cell: background + fill + centered percentage.
/// Lighter than `NSProgressIndicator`, and it keeps a fixed height.
final class ProgressCell: NSView {
    private var value: Double = 0
    private var isError = false
    private var scale: Double = 1.0

    func configure(value: Double, error: Bool, scale: Double = 1.0) {
        self.value = max(0, min(1, value))
        self.isError = error
        self.scale = scale
        needsDisplay = true
    }

    override var wantsDefaultClipping: Bool { true }

    /// A plain `NSView` answers a Ctrl-click with its own (empty) menu instead of passing it
    /// up, so the row's context menu opened everywhere except on the progress bar. Ask the
    /// table instead — the same menu a right-click on this cell gets.
    override func menu(for event: NSEvent) -> NSMenu? {
        var view = superview
        while let v = view, !(v is NSTableView) { view = v.superview }
        return view?.menu(for: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = bounds.insetBy(dx: 2, dy: 5)
        guard bar.width > 2, bar.height > 2 else { return }
        let radius = min(3, bar.height / 2)

        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()

        let fillW = bar.width * CGFloat(value)
        if fillW > 1 {
            let fill = NSRect(x: bar.minX, y: bar.minY, width: fillW, height: bar.height)
            (isError ? NSColor.systemRed : (value >= 1 ? NSColor.systemGreen : NSColor.controlAccentColor)).setFill()
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }

        let pct = "\(Int((value * 100).rounded()))%"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10 * scale, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = pct.size(withAttributes: attrs)
        pct.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}
