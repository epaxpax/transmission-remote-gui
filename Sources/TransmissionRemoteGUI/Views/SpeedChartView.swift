import SwiftUI
import TransmissionKit

/// Time-series speed graph (down/up) drawn with `Canvas` — in the style of the Stats
/// "usage history". No external charting framework needed (works under the CLT toolchain).
/// Download is green, upload is blue (matching the torrent list column colors).
struct SpeedChartView: View {
    let samples: [AppModel.SpeedSample]
    var showBaseline = true

    private let downColor = Color.green
    private let upColor = Color.blue

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1 else { return }
            // Shared scale so download and upload are comparable.
            let peak = max(samples.map { Swift.max($0.down, $0.up) }.max() ?? 1, 1)

            func point(_ index: Int, _ value: Int) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
                let y = size.height * (1 - CGFloat(value) / CGFloat(peak))
                return CGPoint(x: x, y: y)
            }
            func linePath(_ value: (AppModel.SpeedSample) -> Int) -> Path {
                Path { p in
                    for (i, s) in samples.enumerated() {
                        let pt = point(i, value(s))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
            }
            func areaPath(_ value: (AppModel.SpeedSample) -> Int) -> Path {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height))
                    for (i, s) in samples.enumerated() { p.addLine(to: point(i, value(s))) }
                    p.addLine(to: CGPoint(x: size.width, y: size.height))
                    p.closeSubpath()
                }
            }

            if showBaseline {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height - 0.5))
                    p.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                }, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            }

            // Upload behind, download in front (download is usually the taller signal).
            ctx.fill(areaPath { $0.up }, with: .color(upColor.opacity(0.18)))
            ctx.fill(areaPath { $0.down }, with: .color(downColor.opacity(0.20)))
            ctx.stroke(linePath { $0.up }, with: .color(upColor), lineWidth: 1.5)
            ctx.stroke(linePath { $0.down }, with: .color(downColor), lineWidth: 1.5)
        }
    }
}
