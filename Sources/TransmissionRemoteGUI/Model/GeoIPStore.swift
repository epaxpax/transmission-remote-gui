import Foundation
import Observation
import TransmissionKit

/// The bundled IP → country table (`geoip-country.bin`, built by `Scripts/geoip.py` from
/// DB-IP data), loaded off the main thread the first time the Peers tab is shown. Without
/// the file — e.g. under `swift run` — there are simply no flags.
@MainActor @Observable
final class GeoIPStore {
    static let shared = GeoIPStore()
    private(set) var table: GeoIPTable?
    @ObservationIgnored private var requested = false

    func loadIfNeeded() {
        guard !requested else { return }
        requested = true
        Task.detached(priority: .utility) {
            guard let url = Bundle.main.url(forResource: "geoip-country", withExtension: "bin"),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let table = GeoIPTable(compressed: data) else { return }
            await MainActor.run { GeoIPStore.shared.table = table }
        }
    }

    func country(for address: String) -> String? { table?.country(for: address) }
}
