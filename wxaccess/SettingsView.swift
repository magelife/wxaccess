import SwiftUI

struct SettingsView: View {
    @AppStorage("radarOpacity")    private var opacity:       Double = 0.75
    @AppStorage("autoRefresh")     private var autoRefresh:   Bool   = true
    @AppStorage("refreshInterval") private var refreshMins:   Double = 5.0
    @AppStorage("defaultSite")     private var defaultSite:   String = "KEWX"
    @AppStorage("imageSize")       private var imageSize:     Int    = 1024

    var body: some View {
        Form {
            Section("Radar Display") {
                Slider(value: $opacity, in: 0.3...1.0, step: 0.05) {
                    Text("Overlay opacity")
                } minimumValueLabel: {
                    Text("30%")
                } maximumValueLabel: {
                    Text("100%")
                }
                .accessibilityValue(String(format: "%.0f%%", opacity * 100))

                Picker("Image resolution", selection: $imageSize) {
                    Text("512 px (fast)").tag(512)
                    Text("1024 px (default)").tag(1024)
                    Text("2048 px (sharp)").tag(2048)
                }
                .accessibilityLabel("Radar image resolution: \(imageSize) pixels")
            }

            Section("Refresh") {
                Toggle("Auto-refresh", isOn: $autoRefresh)
                if autoRefresh {
                    Picker("Interval", selection: $refreshMins) {
                        Text("2 min").tag(2.0)
                        Text("5 min").tag(5.0)
                        Text("10 min").tag(10.0)
                    }
                }
            }

            Section("Default Site") {
                Picker("Site", selection: $defaultSite) {
                    ForEach(NEXRADSiteCatalog.all) { site in
                        Text(site.displayName).tag(site.icao)
                    }
                }
                .frame(maxWidth: 300)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 420, minHeight: 300)
    }
}
