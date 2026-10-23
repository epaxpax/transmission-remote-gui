import SwiftUI
import TransmissionKit

/// Batch editor for the per-torrent settings of the selected torrents: speed limits,
/// session-limit honouring, bandwidth priority, peer limit and labels.
///
/// Every field starts UNCHANGED and only fields the user actually edits are sent
/// (`TorrentPropertyEdits`). Where the torrents differ, the field shows a mixed state
/// (an indeterminate checkbox, a "Mixed" placeholder or picker entry) instead of
/// pretending one torrent's value is everyone's.
///
/// Like `MoveTorrentView`, the view is model-free: it loads through `load` and reports
/// the result through `onSubmit`.
struct TorrentPropertiesView: View {
    let torrents: [Torrent]
    let labelsSupported: Bool
    let load: () async throws -> [TorrentProperties]
    let onSubmit: (_ edits: TorrentPropertyEdits, _ ids: RPCIds) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Phase { case loading, failed(String), loaded }
    @State private var phase: Phase = .loading
    @State private var current: [TorrentProperties] = []

    // Edited values; nil (or text equal to its initial value) = unchanged.
    @State private var downLimited: Bool?
    @State private var downText = TextEdit()
    @State private var upLimited: Bool?
    @State private var upText = TextEdit()
    @State private var honorsSession: Bool?
    @State private var priority: Int?
    @State private var initialPriority: Int?
    @State private var peerText = TextEdit()

    private enum LabelMode: Hashable { case modify, replace }
    @State private var labelMode = LabelMode.modify
    @State private var addLabelsText = ""
    @State private var removeLabelsText = ""
    @State private var replaceText = TextEdit()

    /// A text field's value plus what it started with, so "edited" means "differs from
    /// what was shown" — clicking into a field and leaving it changes nothing.
    private struct TextEdit {
        var initial = ""
        var text = ""
        var isEdited: Bool {
            text.trimmingCharacters(in: .whitespaces) != initial.trimmingCharacters(in: .whitespaces)
        }
        mutating func reset() { text = initial }

        /// Prefilled with the shared value; empty (showing the placeholder) when mixed.
        static func showing(_ value: MixedValue<Int>) -> TextEdit {
            let text = value.uniformValue.map(String.init) ?? ""
            return TextEdit(initial: text, text: text)
        }
    }

    private var subtitle: String {
        torrents.count == 1
            ? torrents[0].displayName
            : "\(torrents.count) " + loc("kijelölt torrent")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("Torrent tulajdonságai")).font(.title2.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .loaded:
                form
            }

            HStack {
                if case .loaded = phase {
                    Text(loc("Csak a módosított mezők változnak."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(loc("Mégse")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("properties.cancel")
                Button(loc("Alkalmaz")) {
                    guard let edits, !edits.isEmpty else { return }
                    onSubmit(edits, .ids(current.map { RPCIdentifier.id($0.id) }))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(edits?.isEmpty ?? true)
                .accessibilityIdentifier("properties.apply")
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await loadCurrent() }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                limitRow(loc("Letöltési korlát (KB/s)"), id: "download", limited: $downLimited,
                         text: $downText, flag: \.downloadLimited, value: \.downloadLimit)
                limitRow(loc("Feltöltési korlát (KB/s)"), id: "upload", limited: $upLimited,
                         text: $upText, flag: \.uploadLimited, value: \.uploadLimit)
                GridRow {
                    Text(loc("Globális korlátok")).foregroundStyle(.secondary)
                    mixedToggle(loc("A globális sebességkorlátok is érvényesek"),
                                edit: $honorsSession, value: \.honorsSessionLimits)
                        .accessibilityIdentifier("properties.honorsSessionLimits")
                    revertButton("honorsSessionLimits", visible: honorsSession != nil) { honorsSession = nil }
                }
                GridRow {
                    Text(loc("Sávszélesség-prioritás")).foregroundStyle(.secondary)
                    Picker("", selection: $priority) {
                        if initialPriority == nil { Text(loc("Vegyes")).tag(Int?.none) }
                        Text(loc("Alacsony")).tag(Int?.some(BandwidthPriority.low.rawValue))
                        Text(loc("Normál")).tag(Int?.some(BandwidthPriority.normal.rawValue))
                        Text(loc("Magas")).tag(Int?.some(BandwidthPriority.high.rawValue))
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .accessibilityIdentifier("properties.bandwidthPriority")
                    revertButton("bandwidthPriority", visible: priority != initialPriority) { priority = initialPriority }
                }
                GridRow {
                    Text(loc("Peer-limit")).foregroundStyle(.secondary)
                    numberField(text: $peerText, mixed: MixedValue(current, \.peerLimit),
                                valid: TorrentPropertyEdits.parsePeerLimit(peerText.text) != nil)
                        .accessibilityIdentifier("properties.peerLimit")
                    revertButton("peerLimit", visible: peerText.isEdited) { peerText.reset() }
                }
            }

            Divider()
            labelsSection
        }
    }

    /// Checkbox for the "limit on" flag plus the KB/s value, as one row.
    private func limitRow(_ title: String, id: String, limited: Binding<Bool?>, text: Binding<TextEdit>,
                          flag: KeyPath<TorrentProperties, Bool?>,
                          value: KeyPath<TorrentProperties, Int?>) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            HStack {
                mixedToggle(loc("Korlátozva"), edit: limited, value: flag)
                    .accessibilityIdentifier("properties.\(id)Limited")
                numberField(text: text, mixed: MixedValue(current, { $0[keyPath: value] }),
                            valid: TorrentPropertyEdits.parseSpeedLimit(text.wrappedValue.text) != nil)
                    .accessibilityIdentifier("properties.\(id)Limit")
            }
            revertButton("\(id)Limit", visible: limited.wrappedValue != nil || text.wrappedValue.isEdited) {
                limited.wrappedValue = nil
                text.wrappedValue.reset()
            }
        }
    }

    /// A checkbox that shows the native mixed state while the torrents disagree and the
    /// user has not touched it. Clicking it sets one value for all of them.
    private func mixedToggle(_ title: String, edit: Binding<Bool?>,
                             value: KeyPath<TorrentProperties, Bool?>) -> some View {
        let sources = current.map { torrent in
            Binding<Bool>(get: { edit.wrappedValue ?? torrent[keyPath: value] ?? false },
                          set: { edit.wrappedValue = $0 })
        }
        return Toggle(title, sources: sources, isOn: \.self)
    }

    private func numberField(text: Binding<TextEdit>, mixed: MixedValue<Int>, valid: Bool) -> some View {
        let edited = text.wrappedValue.isEdited
        return TextField("", text: text.text, prompt: Text(mixed.isMixed ? loc("Vegyes") : "—"))
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .foregroundStyle(edited && !valid ? Color.red : Color.primary)
    }

    private func revertButton(_ id: String, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .help(loc("Eredeti érték visszaállítása"))
        .opacity(visible ? 1 : 0)
        .disabled(!visible)
        .accessibilityIdentifier("properties.revert.\(id)")
    }

    // MARK: Labels

    private var labelLists: [[String]] { current.map { $0.labels ?? [] } }

    @ViewBuilder
    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("Címkék")).font(.callout.bold())
            if !labelsSupported {
                Text(loc("A címkékhez Transmission 3.00 vagy újabb kell."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let common = TorrentLabels.common(labelLists)
                let partial = TorrentLabels.partial(labelLists)
                Text(loc("Mindegyiken:") + " " + (common.isEmpty ? "—" : common.joined(separator: ", ")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !partial.isEmpty {
                    Text(loc("Csak némelyiken:") + " " + partial.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Picker("", selection: $labelMode) {
                    Text(loc("Hozzáadás / eltávolítás")).tag(LabelMode.modify)
                    Text(loc("Összes cseréje")).tag(LabelMode.replace)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("properties.labelMode")

                switch labelMode {
                case .modify:
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text(loc("Hozzáadandó")).foregroundStyle(.secondary)
                            TextField("", text: $addLabelsText, prompt: Text(loc("címke1, címke2")))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("properties.labelsAdd")
                        }
                        GridRow {
                            Text(loc("Eltávolítandó")).foregroundStyle(.secondary)
                            TextField("", text: $removeLabelsText, prompt: Text(loc("címke1, címke2")))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("properties.labelsRemove")
                        }
                    }
                    Text(loc("A többi meglévő címke megmarad."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .replace:
                    TextField("", text: $replaceText.text,
                              prompt: Text(MixedValue(labelLists, { $0 }).isMixed ? loc("Vegyes") : loc("címke1, címke2")))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("properties.labelsReplace")
                    Text(loc("Minden kijelölt torrent összes címkéjét erre a listára cseréli."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Edits

    /// The edits to send, or nil while an edited field does not parse.
    private var edits: TorrentPropertyEdits? {
        guard case .loaded = phase else { return nil }
        var edits = TorrentPropertyEdits()
        edits.downloadLimited = downLimited
        edits.uploadLimited = upLimited
        edits.honorsSessionLimits = honorsSession
        if priority != initialPriority, let priority {
            edits.bandwidthPriority = BandwidthPriority(rawValue: priority)
        }
        if downText.isEdited {
            guard let value = TorrentPropertyEdits.parseSpeedLimit(downText.text) else { return nil }
            edits.downloadLimit = value
        }
        if upText.isEdited {
            guard let value = TorrentPropertyEdits.parseSpeedLimit(upText.text) else { return nil }
            edits.uploadLimit = value
        }
        if peerText.isEdited {
            guard let value = TorrentPropertyEdits.parsePeerLimit(peerText.text) else { return nil }
            edits.peerLimit = value
        }
        if labelsSupported {
            switch labelMode {
            case .modify:
                let add = TorrentLabels.parse(addLabelsText)
                let remove = TorrentLabels.parse(removeLabelsText)
                if !add.isEmpty || !remove.isEmpty { edits.labels = .modify(add: add, remove: remove) }
            case .replace:
                if TorrentLabels.parse(replaceText.text) != TorrentLabels.parse(replaceText.initial) {
                    edits.labels = .replace(TorrentLabels.parse(replaceText.text))
                }
            }
        }
        return edits
    }

    // MARK: Loading

    private func loadCurrent() async {
        do {
            let loaded = try await load()
            guard !loaded.isEmpty else {
                phase = .failed(loc("A kijelölt torrentek már nem érhetők el."))
                return
            }
            current = loaded
            downText = TextEdit.showing(MixedValue(loaded, \.downloadLimit))
            upText = TextEdit.showing(MixedValue(loaded, \.uploadLimit))
            peerText = TextEdit.showing(MixedValue(loaded, \.peerLimit))
            initialPriority = MixedValue(loaded, \.bandwidthPriority).uniformValue
            priority = initialPriority
            let labels = MixedValue(loaded.map { $0.labels ?? [] }, { $0 })
            let initialLabels = labels.uniformValue?.joined(separator: ", ") ?? ""
            replaceText = TextEdit(initial: initialLabels, text: initialLabels)
            phase = .loaded
        } catch {
            phase = .failed(locError(error))
        }
    }
}
