import SwiftUI
import TransmissionKit

/// Detailed statistics panel: current speeds, a large speed graph, and cumulative totals.
struct StatisticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var globalRatio: Double {
        let d = model.totalDownloaded
        return d > 0 ? Double(model.totalUploaded) / Double(d) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(loc("Statisztika")).font(.title2.bold())
                Spacer()
                Button(loc("Kész")) { dismiss() }.keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 44) {
                bigStat(loc("Letöltés"), Format.rateOrZero(model.sessionStats?.downloadSpeed ?? 0), .green)
                bigStat(loc("Feltöltés"), Format.rateOrZero(model.sessionStats?.uploadSpeed ?? 0), .blue)
            }

            SpeedChartView(samples: model.speedHistory)
                .frame(height: 150)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                statRow(loc("Összes letöltve"), Format.size(model.totalDownloaded))
                statRow(loc("Összes feltöltve"), Format.size(model.totalUploaded))
                statRow(loc("Arány"), Format.ratio(globalRatio))
                statRow(loc("Aktív torrentek"), "\(model.activeTorrentCount) / \(model.torrents.count)")
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 420)
    }

    private func bigStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title.monospacedDigit().bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }
}
