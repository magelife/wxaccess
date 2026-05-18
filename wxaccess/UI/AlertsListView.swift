import SwiftUI

struct AlertsListView: View {
    @Environment(AppState.self) var appState
    @State private var selected: NWSAlert?

    var body: some View {
        List(appState.alerts, selection: $selected) { alert in
            alertRow(alert)
                .tag(alert)
        }
        .navigationTitle("Active Alerts")
        .overlay {
            if appState.alerts.isEmpty {
                ContentUnavailableView(
                    "No Active Alerts",
                    systemImage: "checkmark.shield",
                    description: Text("No watches, warnings, or advisories near \(appState.selectedSite.icao).")
                )
            }
        }
        .sheet(item: $selected) { alert in
            AlertDetailView(alert: alert)
        }
    }

    private func alertRow(_ alert: NWSAlert) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(severityColor(alert.severity))
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.event)
                    .font(.subheadline.weight(.semibold))
                Text(alert.senderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Until \(alert.expires.formatted(date: .abbreviated, time: .shortened)) UTC")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(alert.accessibilityLabel)
    }

    private func severityColor(_ s: NWSAlert.Severity) -> Color {
        switch s {
        case .extreme:  .red
        case .severe:   .orange
        case .moderate: .yellow
        default:        .gray
        }
    }
}

struct AlertDetailView: View {
    let alert: NWSAlert
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(alert.event)
                    .font(.title2.weight(.bold))
                Text(alert.headline)
                    .font(.body)
                    .foregroundStyle(.secondary)
                if !alert.description.isEmpty {
                    Divider()
                    Text("Description")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(alert.description)
                        .font(.body)
                }
                if !alert.instruction.isEmpty {
                    Divider()
                    Text("What to Do")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(alert.instruction)
                        .font(.body)
                }
                Divider()
                Group {
                    LabeledContent("Issued by", value: alert.senderName)
                    LabeledContent("Effective", value: alert.effective.formatted(date: .abbreviated, time: .shortened) + " UTC")
                    LabeledContent("Expires",   value: alert.expires.formatted(date: .abbreviated, time: .shortened) + " UTC")
                }
                .font(.caption)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
