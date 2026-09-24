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
    @State private var preview: [PlannedChange]?
    /// Whether the last preview fetch failed (vs. genuinely finding nothing to change) —
    /// see `RulePreviewView.couldNotDetermine`.
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("Szabály")).font(.title2.bold())

            TextField(loc("Név"), text: $name).textFieldStyle(.roundedBorder)

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
                        // Clear any stale error first: an empty result below must reflect
                        // *this* fetch's outcome, not one left over from an earlier action.
                        model.actionError = nil
                        let result = await model.previewRules([built], force: true)
                        preview = result
                        previewFailed = result.isEmpty && model.actionError != nil
                    }
                }
                Spacer()
                Button(loc("Mégse")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(loc("Mentés")) { onSave(built); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(conditionValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .sheet(item: Binding(get: { preview.map(EditorPlanBox.init) },
                             set: { if $0 == nil { preview = nil } })) { box in
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

    private var built: TorrentRule {
        let condition: RuleCondition
        switch conditionKind {
        case .tracker: condition = .trackerHost(conditionValue)
        case .label: condition = .label(conditionValue)
        case .name: condition = .namePattern(conditionValue)
        }
        var actions = RuleActions()
        if ratioOn { actions.seedRatio = Double(ratio.replacingOccurrences(of: ",", with: ".")) }
        if idleOn { actions.seedIdleMinutes = Int(idle) }
        if upOn { actions.uploadLimitKBps = Int(up) }
        if downOn { actions.downloadLimitKBps = Int(down) }
        if labelsOn {
            actions.addLabels = labelsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        actions.stop = stop
        return TorrentRule(id: ruleID, name: name, enabled: true,
                           condition: condition, actions: actions)
    }
}

private struct EditorPlanBox: Identifiable {
    let id = UUID()
    let plan: [PlannedChange]
}
