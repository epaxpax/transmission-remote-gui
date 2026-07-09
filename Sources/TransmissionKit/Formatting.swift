import Foundation

/// Display formatters for the UI (part of the kit so they are testable and reusable).
public enum Format {
    private static func makeByteFormatter() -> ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }

    /// Human-readable size, e.g. "1,4 GB".
    public static func size(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 B" }
        return makeByteFormatter().string(fromByteCount: Int64(bytes))
    }

    /// Speed, e.g. "1,2 MB/s". Returns an empty string for 0.
    public static func rate(_ bytesPerSecond: Int) -> String {
        guard bytesPerSecond > 0 else { return "" }
        return makeByteFormatter().string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    /// Speed, "0 B/s" for 0 (for status rows where an empty string is confusing).
    public static func rateOrZero(_ bytesPerSecond: Int) -> String {
        bytesPerSecond > 0 ? rate(bytesPerSecond) : "0 B/s"
    }

    /// Percentage, e.g. "47%".
    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Ratio, e.g. "1.85". "∞" / "—" for -1/-2.
    public static func ratio(_ value: Double) -> String {
        if value < 0 { return "∞" }
        return String(format: "%.2f", value)
    }

    /// Remaining time. -1 = unknown, -2 = infinite.
    public static func eta(_ seconds: Int) -> String {
        switch seconds {
        case ..<0: return "—"
        case 0: return "0s"
        default:
            let d = seconds / 86400
            let h = (seconds % 86400) / 3600
            let m = (seconds % 3600) / 60
            let s = seconds % 60
            // Language-independent abbreviations (d/h/m/s) — international, like GB/MB.
            if d > 0 { return "\(d)d \(h)h" }
            if h > 0 { return "\(h)h \(m)m" }
            if m > 0 { return "\(m)m \(s)s" }
            return "\(s)s"
        }
    }
}
