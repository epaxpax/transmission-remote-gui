import SwiftUI
import TransmissionKit

struct RuleEditorView: View {
    let onSave: (TorrentRule) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var conditionKind: ConditionKind
    @State private var conditionValue: String
    @State private var ratioOn: Bool
    @State private var ratio: String
    @State private var idleOn: Bool
    @State private var idle: String
    @State private var upOn: Bool
    @State private var up: String
    @State private var downOn: Bool
    @State private var down: String
    @State private var labelsOn: Bool
    @State private var labelsText: String
    @State private var stop: Bool
    /// The rule's enabled/paused state. Must be carried through unchanged unless the
    /// user explicitly toggles it here — an unrelated edit (e.g. renaming) must never
    /// silently re-enable a rule the user deliberately paused.
    @State private var enabled: Bool
    /// Backs the nested preview sheet. Stored as `@State` (not derived inside the
    /// `.sheet(item:)` binding's getter) so its identity is stable across unrelated
    /// `body` re-evaluations while the sheet is open — a fresh `UUID` on every getter
    /// call would risk SwiftUI treating it as a new item and re-presenting the sheet.
    @State private var previewBox: EditorPlanBox?
    /// Whether the last preview fetch failed (vs. genuinely finding nothing to change) —
    /// see `RulePreviewView.couldNotDetermine`. Comes straight from `AppModel.previewRules`'s
    /// `failed` flag, not from a heuristic over the shared `actionError`.
    @State private var previewFailed = false

    private let ruleID: UUID

    enum ConditionKind: String, CaseIterable, Identifiable {
        case tracker, label, name
        var id: String { rawValue }
        // `ConditionKind` is a nested type, not `RuleEditorView` itself, so it does not
        // inherit the enclosing view's inferred @MainActor isolation — spelled out here
        // so `title` may call the @MainActor `loc()`.
        @MainActor var title: String {
            switch self {
            case .tracker: return loc("tracker-host")
            case .label: return loc("címke")
            case .name: return loc("név-minta")
            }
        }
    }

    init(rule: TorrentRule, onSave: @escaping (TorrentRule) -> Void) {
        self.onSave = onSave
        self.ruleID = rule.id
        _name = State(initialValue: rule.name)
        switch rule.condition {
        case .trackerHost(let v): _conditionKind = State(initialValue: .tracker); _conditionValue = State(initialValue: v)
        case .label(let v): _conditionKind = State(initialValue: .label); _conditionValue = State(initialValue: v)
        case .namePattern(let v): _conditionKind = State(initialValue: .name); _conditionValue = State(initialValue: v)
        }
        _ratioOn = State(initialValue: rule.actions.seedRatio != nil)
        _ratio = State(initialValue: rule.actions.seedRatio.map { String($0) } ?? "2.0")
        _idleOn = State(initialValue: rule.actions.seedIdleMinutes != nil)
        _idle = State(initialValue: rule.actions.seedIdleMinutes.map(String.init) ?? "30")
        _upOn = State(initialValue: rule.actions.uploadLimitKBps != nil)
        _up = State(initialValue: rule.actions.uploadLimitKBps.map(String.init) ?? "")
        _downOn = State(initialValue: rule.actions.downloadLimitKBps != nil)
        _down = State(initialValue: rule.actions.downloadLimitKBps.map(String.init) ?? "")
        _labelsOn = State(initialValue: !rule.actions.addLabels.isEmpty)
        _labelsText = State(initialValue: rule.actions.addLabels.joined(separator: ", "))
        _stop = State(initialValue: rule.actions.stop)
        _enabled = State(initialValue: rule.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("Szabály")).font(.title2.bold())

            TextField(loc("Név"), text: $name).textFieldStyle(.roundedBorder)
            Toggle(loc("Szabály bekapcsolva"), isOn: $enabled)

            HStack {
                Text(loc("Ha a"))
                Picker("", selection: $conditionKind) {
                    ForEach(ConditionKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 150)
                TextField("", text: $conditionValue).textFieldStyle(.roundedBorder)
            }

            Text(loc("Akkor")).font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, verticalSpacing: 6) {
                actionRow(loc("Seed arány"), isOn: $ratioOn, value: $ratio)
                actionRow(loc("Leállítás üresjárat után (perc)"), isOn: $idleOn, value: $idle)
                actionRow(loc("Feltöltési korlát (KB/s)"), isOn: $upOn, value: $up)
                actionRow(loc("Letöltési korlát (KB/s)"), isOn: $downOn, value: $down)
                actionRow(loc("Címke hozzáadása"), isOn: $labelsOn, value: $labelsText)
                GridRow {
                    Toggle(loc("Azonnali leállítás"), isOn: $stop).gridCellColumns(2)
                }
            }

            HStack {
                Button(loc("Mit változtatna?")) {
                    Task {
                        // Preview an *enabled* copy. `RuleEngine.plan` filters to enabled
                        // rules, so previewing `built` while the "Szabály bekapcsolva"
                        // toggle is off returns an empty plan and the sheet says "nothing
                        // would change" — for the wrong reason. The question this button
                        // answers is "what would this rule do", not "is it switched on
                        // right now". (`RulesView` guards its post-save offer the other
                        // way, by not offering it at all for a disabled rule; here the
                        // user pressed the button deliberately.)
                        var probe = built
                        probe.enabled = true
                        let result = await model.previewRules([probe], force: true)
                        previewFailed = result.failed
                        previewBox = EditorPlanBox(plan: result.plan)
                    }
                }
                Spacer()
                Button(loc("Mégse")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(loc("Mentés")) { onSave(built); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .sheet(item: $previewBox) { box in
            RulePreviewView(plan: box.plan, onApply: { }, couldNotDetermine: previewFailed)   // preview only: no apply from the editor
        }
    }

    @ViewBuilder
    private func actionRow(_ title: String, isOn: Binding<Bool>, value: Binding<String>) -> some View {
        GridRow {
            Toggle(title, isOn: isOn)
            TextField("", text: value).textFieldStyle(.roundedBorder)
                .frame(width: 120).disabled(!isOn.wrappedValue)
        }
    }

    /// Whether every *enabled* field actually parses. Mirrors `MoveTorrentView`'s
    /// `sanitized`-gates-the-primary-button pattern: a ticked checkbox whose field
    /// fails to parse must block Mentés, not silently become "no action" — the user
    /// believes they set a limit, and the saved rule would otherwise do nothing for it.
    private var isValid: Bool {
        guard !conditionValue.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if ratioOn && Self.parseDouble(ratio) == nil { return false }
        if idleOn && Self.parseInt(idle) == nil { return false }
        if upOn && Self.parseInt(up) == nil { return false }
        if downOn && Self.parseInt(down) == nil { return false }
        return true
    }

    /// Parses a decimal field, accepting a comma as the decimal separator — Hungarian
    /// keyboards produce commas, not periods.
    private static func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// Parses a whole-number field. Accepts a plain integer, and — same comma-as-decimal
    /// convention as `parseDouble` — a comma/period decimal rounded to the nearest whole
    /// number, so a mistyped "50,5" in an upload/download field doesn't fail silently.
    private static func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let value = Int(trimmed) { return value }
        guard let decimal = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return Int(decimal.rounded())
    }

    private var built: TorrentRule {
        let condition: RuleCondition
        switch conditionKind {
        case .tracker: condition = .trackerHost(conditionValue)
        case .label: condition = .label(conditionValue)
        case .name: condition = .namePattern(conditionValue)
        }
        var actions = RuleActions()
        if ratioOn { actions.seedRatio = Self.parseDouble(ratio) }
        if idleOn { actions.seedIdleMinutes = Self.parseInt(idle) }
        if upOn { actions.uploadLimitKBps = Self.parseInt(up) }
        if downOn { actions.downloadLimitKBps = Self.parseInt(down) }
        if labelsOn {
            actions.addLabels = labelsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        actions.stop = stop
        return TorrentRule(id: ruleID, name: name, enabled: enabled,
                           condition: condition, actions: actions)
    }
}

private struct EditorPlanBox: Identifiable {
    let id = UUID()
    let plan: [PlannedChange]
}
