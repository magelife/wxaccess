import SwiftUI
import MapKit

@Observable
@MainActor
final class AppState {
    var selectedSite: NEXRADSite = NEXRADSiteCatalog.site(icao: "KEWX") ?? NEXRADSiteCatalog.all[0]
    var selectedProduct: RadarProduct = .reflectivity
    var currentSweep: RadarSweep?
    var availableScans: [ScanEntry] = []
    var selectedScan: ScanEntry?
    var alerts: [NWSAlert] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var animating: Bool = false
    var showAbout: Bool = false
    var tiltIndex: Int = 0

    var statusDescription: String {
        if isLoading { return "Loading…" }
        if let sweep = currentSweep {
            return "\(sweep.site.icao) \(selectedProduct.displayName) \(String(format: "%.1f", sweep.elevationAngle))° — \(sweep.scanTime.formatted(date: .omitted, time: .shortened))"
        }
        return "No data loaded"
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            availableScans = try await Level2Fetcher.shared.listScans(site: selectedSite)
            if let latest = availableScans.first {
                selectedScan = latest
                await loadScan(latest)
            }
            alerts = try await AlertsFetcher.shared.fetchAlerts(near: selectedSite.coordinate)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadScan(_ entry: ScanEntry) async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await Level2Fetcher.shared.download(entry: entry)
            let decoder = Level2Decoder()
            let sweeps = try decoder.decode(data: data)
            currentSweep = sweeps.first(where: { abs($0.elevationAngle - tiltAngle(for: tiltIndex)) < 0.5 })
                ?? sweeps.first
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func tiltAngle(for index: Int) -> Double {
        let tilts: [Double] = [0.5, 1.45, 2.4, 3.35, 4.3]
        return index < tilts.count ? tilts[index] : tilts[0]
    }
}

enum RadarProduct: String, CaseIterable, Identifiable {
    case reflectivity = "REF"
    case velocity = "VEL"
    case spectrumWidth = "SW"
    case differentialReflectivity = "ZDR"
    case correlationCoefficient = "RHO"
    case differentialPhase = "PHI"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reflectivity: "Reflectivity"
        case .velocity: "Velocity"
        case .spectrumWidth: "Spectrum Width"
        case .differentialReflectivity: "Diff. Reflectivity"
        case .correlationCoefficient: "Corr. Coefficient"
        case .differentialPhase: "Diff. Phase"
        }
    }
}
