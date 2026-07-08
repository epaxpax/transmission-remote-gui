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

    private static let baseRowHeight: CGFloat = 22
    private static let baseFontSize: CGFloat = 12

    // MARK: Column specs

    struct ColumnSpec {
        let id: String
        let title: String
        let width: CGFloat
        let minWidth: CGFloat
        let alignment: NSTextAlignment
        let monospaced: Bool
        let isProgress: Bool
        let text: (Torrent) -> String
        let color: (Torrent) -> NSColor?
        let makeComparator: (_ ascending: Bool) -> KeyPathComparator<Torrent>

        init(id: String, title: String, width: CGFloat, minWidth: CGFloat = 40,
             alignment: NSTextAlignment = .left, monospaced: Bool = false, isProgress: Bool = false,
             text: @escaping (Torrent) -> String = { _ in "" },
             color: @escaping (Torrent) -> NSColor? = { _ in nil },
             comparator: @escaping (_ ascending: Bool) -> KeyPathComparator<Torrent>) {
            self.id = id; self.title = title; self.width = width; self.minWidth = minWidth
            self.alignment = alignment; self.monospaced = monospaced; self.isProgress = isProgress
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
        ColumnSpec(id: "down", title: "↓", width: 78, alignment: .right, monospaced: true,
                   text: { Format.rate($0.downloadRate) },
                   color: { _ in .systemGreen },
                   comparator: { KeyPathComparator(\Torrent.downloadRate, order: $0 ? .forward : .reverse) }),
        ColumnSpec(id: "up", title: "↑", width: 78, alignment: .right, monospaced: true,
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
    ]

    static let columnsByID: [String: ColumnSpec] = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    // MARK: NSViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
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
            table.addTableColumn(col)
        }

        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked)

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
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: TorrentTableView
        weak var tableView: NSTableView?
        var data: [Torrent] = []
        private var isSyncingSelection = false
        private var lastScale: Double = 1.0
        private var lastLanguage: AppLanguage?

        init(_ parent: TorrentTableView) { self.parent = parent }

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
