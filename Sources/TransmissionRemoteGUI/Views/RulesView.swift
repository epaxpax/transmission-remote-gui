import SwiftUI
import TransmissionKit

/// The rules manager: an ordered list where the first matching rule wins, so the order
/// is meaningful and must be editable.
struct RulesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selection: TorrentRule.ID?
    @State private var editing: TorrentRule?
    @State private var preview: [PlannedChange]?
    /// See `RulePreviewView.couldNotDetermine`: comes straight from `AppModel.previewRules`'s
    /// `failed` flag for whichever preview is currently showing (manual run or the
    /// post-save retroactive offer), never from a heuristic over `model.actionError`.
    @State private var previewFailed = false
    @State private var running = false

    var body: some View {
        // The store needs its own @Bindable: `$model.ruleStore.enabled` would not compile,
        // because `ruleStore` is a `let` on `AppModel`, and a binding must reach into the
        // nested @Observable object itself, not through a `let` that holds it.
        @Bindable var store = model.ruleStore
        let selected = store.rules.first { $0.id == selection }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc("Szabályok")).font(.title2.bold())
                Spacer()
                Toggle(loc("Bekapcsolva"), isOn: $store.enabled)
                    .toggleStyle(.switch)
            }

            Text(loc("Az első illeszkedő szabály érvényesül, ezért a sorrend számít."))
                .font(.caption).foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(store.rules) { rule in
                    RuleRow(rule: rule) { toggled in
                        if let i = store.rules.firstIndex(where: { $0.id == rule.id }) {
                            store.rules[i].enabled = toggled
                        }
                    }
                    .tag(rule.id)
                }
                .onMove { from, to in store.rules.move(fromOffsets: from, toOffset: to) }
            }
            .frame(minHeight: 220)

            HStack {
                Button(loc("Új szabály")) {
                    editing = TorrentRule(name: loc("Új szabály"),
                                          condition: .trackerHost(""),
                                          actions: RuleActions())
                }
                Button(loc("Szerkesztés")) { editing = selected }
                    .disabled(selected == nil)
                Button(loc("Törlés"), role: .destructive) {
                    store.rules.removeAll { $0.id == selection }
                    selection = nil
                }
                .disabled(selected == nil)
                Spacer()
                Button(loc("Futtatás most…")) { Task { await runNow(store.rules) } }
                    .disabled(running || store.rules.isEmpty)
            }

            if let last = store.lastRun {
                Text(summary(last)).font(.caption).foregroundStyle(.secondary)
            }

            HStack { Spacer(); Button(loc("Kész")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 620, height: 480)
        .sheet(item: $editing) { rule in
            RuleEditorView(rule: rule) { saved in
                if let i = store.rules.firstIndex(where: { $0.id == saved.id }) {
                    store.rules[i] = saved
                } else {
                    store.rules.append(saved)
                }
                // The engine classifies each torrent once and never re-evaluates it, so a
                // rule saved after the library is already classified would otherwise match
                // nothing — the user would see it silently do nothing. Offer the same
                // preview-then-apply flow "Futtatás most…" uses, scoped to just this rule,
                // so the user can see and apply its effect on the existing library right
                // away. Declining (Cancel in the preview) is harmless: the rule stays saved
                // and still applies to newly added torrents from then on.
                //
                // Only when the saved rule is enabled: `RuleEngine.plan` filters to enabled
                // rules before matching, so a disabled rule always yields an empty plan —
                // offering the dry run for one would show "nothing would change" for the
                // wrong reason (disabled, not merely non-matching), which is worse than not
                // offering it at all.
                if saved.enabled {
                    Task { await offerRetroactiveRun(for: saved) }
                }
            }
            .environment(model)
        }
        .sheet(item: Binding(get: { preview.map(PlanBox.init) },
                             set: { if $0 == nil { preview = nil } })) { box in
            RulePreviewView(plan: box.plan, onApply: {
                Task { await model.applyPlan(box.plan); preview = nil }
            }, couldNotDetermine: previewFailed)
        }
    }

    /// "Run now" deliberately forces: the point is to reach torrents an earlier pass
    /// already classified.
    private func runNow(_ rules: [TorrentRule]) async {
        running = true
        defer { running = false }
        let result = await model.previewRules(rules, force: true)
        previewFailed = result.failed
        preview = result.plan
    }

    /// Offers to run a just-saved rule against the existing library. Reuses the exact
    /// same preview-then-apply flow as "Futtatás most…" (the same `preview` sheet), just
    /// scoped to the one rule that was saved, and always forced — same reasoning as
    /// `runNow`: reaching torrents an earlier pass already classified is the whole point.
    private func offerRetroactiveRun(for rule: TorrentRule) async {
        let result = await model.previewRules([rule], force: true)
        previewFailed = result.failed
        preview = result.plan
    }

    private func summary(_ run: RunSummary) -> String {
        let when = RulesView.formatter.string(from: run.date)
        return "\(loc("Utolsó futás")): \(when) — \(run.applied) \(loc("alkalmazva")), \(run.failed) \(loc("sikertelen"))"
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()
}

/// `.sheet(item:)` needs an Identifiable payload; a plan is a plain array.
private struct PlanBox: Identifiable {
    let id = UUID()
    let plan: [PlannedChange]
}

private struct RuleRow: View {
    let rule: TorrentRule
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { toggled in onToggle(toggled) }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.body)
                Text(RuleSummary.condition(rule.condition) + " → " + RuleSummary.actions(rule.actions))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Short human-readable descriptions, shared by the list and the editor.
///
/// Not a nested type, so — unlike `RuleEditorView.ConditionKind` — it does not inherit any
/// enclosing view's inferred @MainActor isolation; spelled out here so its static methods
/// may call the @MainActor `loc()`.
@MainActor
enum RuleSummary {
    static func condition(_ c: RuleCondition) -> String {
        switch c {
        case .trackerHost(let v): return "\(loc("tracker")) = \(v)"
        case .label(let v): return "\(loc("címke")) = \(v)"
        case .namePattern(let v): return "\(loc("név")) ~ \(v)"
        }
    }

    static func actions(_ a: RuleActions) -> String {
        var parts: [String] = []
        if let r = a.seedRatio { parts.append("\(loc("arány")) \(r)") }
        // "m" for minutes, not the Hungarian "p" (perc): a language-independent
        // abbreviation, same convention as Format.eta's d/h/m/s.
        if let i = a.seedIdleMinutes { parts.append("\(loc("üresjárat")) \(i)m") }
        if let u = a.uploadLimitKBps { parts.append("↑ \(u)") }
        if let d = a.downloadLimitKBps { parts.append("↓ \(d)") }
        if !a.addLabels.isEmpty { parts.append("+\(a.addLabels.joined(separator: ","))") }
        if a.stop { parts.append(loc("leállítás")) }
        return parts.isEmpty ? loc("nincs akció") : parts.joined(separator: " · ")
    }
}
