import SwiftUI

// The VoiceOver-first data panel. Sighted users see a compact summary strip;
// VoiceOver users navigate a structured set of live regions that mirror
// everything shown visually on the map.
struct AccessibilityPanel: View {
    @Environment(AppState.self) var appState

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                radarSection
                Divider()
                alertsSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } label: {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("Data Summary")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !appState.alerts.isEmpty {
                    alertBadge
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.background.secondary)
        // Live region: VoiceOver announces when the status changes
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weather data summary")
    }

    // MARK: - Radar section

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Radar", systemImage: "waveform.path.ecg")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let sweep = appState.currentSweep {
                Group {
                    dataRow(label: "Site",    value: sweep.site.displayName)
                    dataRow(label: "Product", value: appState.selectedProduct.displayName)
                    dataRow(label: "Tilt",    value: String(format: "%.1f°", sweep.elevationAngle))
                    dataRow(label: "Time",    value: sweep.scanTime.formatted(date: .abbreviated, time: .shortened) + " UTC")
                    dataRow(label: "VCP",     value: "\(sweep.vcpNumber)")
                    dataRow(label: "Gates",   value: "\(sweep.radials.first?.numGates ?? 0) at \(sweep.radials.first?.gateSizeMeters ?? 0) m spacing")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Radar sweep details")
            } else {
                Text(appState.isLoading ? "Loading radar data…" : "No radar data loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    // MARK: - Alerts section

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Active Alerts", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if appState.alerts.isEmpty {
                Text("No active watches, warnings, or advisories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.alerts) { alert in
                    alertRow(alert)
                }
            }
        }
        // Announce changes to this group automatically
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active weather alerts")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func alertRow(_ alert: NWSAlert) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(severityColor(alert.severity))
                .font(.caption)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.event)
                    .font(.caption.weight(.semibold))
                Text(alert.headline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Expires \(alert.expires.formatted(date: .omitted, time: .shortened)) UTC")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(alert.accessibilityLabel)
    }

    private var alertBadge: some View {
        Text("\(appState.alerts.count)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.red)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .accessibilityLabel("\(appState.alerts.count) active alert\(appState.alerts.count == 1 ? "" : "s")")
    }

    // MARK: - Helpers

    private func dataRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func severityColor(_ severity: NWSAlert.Severity) -> Color {
        switch severity {
        case .extreme:  .red
        case .severe:   .orange
        case .moderate: .yellow
        default:        .white
        }
    }
}
