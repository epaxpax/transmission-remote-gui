import SwiftUI
import TransmissionKit

/// The dry run. Since the app has no automated UI tests, this view doubles as the
/// user's own verification step: nothing leaves the app before they have seen it.
struct RulePreviewView: View {
    let plan: [PlannedChange]
    let onApply: () -> Void
    /// `AppModel.previewRules(_:force:)` returns an empty `plan` in two different
    /// situations: nothing matched, or the fetch failed (in which case `AppModel`
    /// also sets `actionError`, surfaced as an alert elsewhere). An empty plan alone
    /// cannot tell them apart, so the caller passes this flag when it knows the
    /// fetch failed — showing "could not determine" instead of the "nothing would
    /// change" text, which would otherwise read as contradicting the error alert.
    /// Defaults to the "no changes" reading, the ordinary case.
    var couldNotDetermine: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("Mit változtatna")).font(.title2.bold())

            if plan.isEmpty {
                Text(couldNotDetermine
                     ? loc("Nem sikerült ellenőrizni a változásokat.")
                     : loc("Egyetlen torrenten sem változna semmi."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(plan) {
                    // Fixed name columns leave the rest to "Változás": with three equal
                    // columns a status change ("Downloading → Stopped") was cut off.
                    TableColumn(loc("Torrent"), value: \.torrentName)
                        .width(170)
                    TableColumn(loc("Szabály"), value: \.ruleName)
                        .width(130)
                    // One line per field change rather than a single delimiter-joined
                    // string: `RuleEngine.plan` always appends `.stop` last, and a
                    // single-line column truncates exactly that tail first — the one
                    // change that must never look absent. The stop line is also made
                    // visually distinct (icon + bold) so it can't be missed even among
                    // several other changes.
                    TableColumn(loc("Változás")) { change in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(change.changes.enumerated()), id: \.offset) { _, fieldChange in
                                Self.row(for: fieldChange)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                    }
                }
                .frame(minHeight: 260)
            }

            HStack {
                Spacer()
                Button(loc("Mégse")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(loc("Alkalmazás")) { onApply(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 700, height: 420)
    }

    @ViewBuilder
    static func row(for change: FieldChange) -> some View {
        if change.field == .stop {
            Label(describe(change), systemImage: "stop.circle.fill")
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
        } else {
            Text(describe(change))
        }
    }

    static func describe(_ change: FieldChange) -> String {
        // `.stop` is the one row whose before/after are prose, not data: they come from
        // `Torrent.statusText` and `Torrent.Status.stopped.text`, Hungarian strings built
        // in TransmissionKit — which by design contains no `loc()` calls at all. Run just
        // those through `locStatus`, exactly as the table's status column does, or an
        // English user reads "Status: Seedelés → Leállítva" in the dry run, the one
        // surface the design makes their safeguard. The other five fields are numbers and
        // label lists and must NOT go through `locStatus`.
        if change.field == .stop {
            return "\(label(change.field)): \(locStatus(change.before)) → \(locStatus(change.after))"
        }
        return "\(label(change.field)): \(change.before) → \(change.after)"
    }

    static func label(_ field: RuleField) -> String {
        switch field {
        case .seedRatio: return loc("Seed arány")
        case .seedIdle: return loc("Üresjárati limit (perc)")
        case .uploadLimit: return loc("Feltöltési korlát")
        case .downloadLimit: return loc("Letöltési korlát")
        case .labels: return loc("Címkék")
        case .stop: return loc("Állapot")
        }
    }
}
