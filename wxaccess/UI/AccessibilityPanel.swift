import SwiftUI

// The VoiceOver-first data panel. Sighted users see a compact summary strip;
// VoiceOver users navigate a structured set of live regions that mirror
// everything shown visually on the map.
struct AccessibilityPanel: View {
    @Environment(AppState.self) var appState

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                paneSummarySection
                Divider()
                radarSection
                if let probe = appState.probeResult {
                    Divider(); probeSection(probe)
                }
                if appState.isAnimating || appState.hasAnimationFrames {
                    Divider(); animationSection
                }
                Divider(); sonificationSection
                Divider(); alertsSection
                Divider(); outlooksSection
                if appState.showMesoscaleDiscussions {
                    Divider(); mdSection
                }
                if appState.showStormReports {
                    Divider(); stormReportsSection
                }
                if appState.showStormCells {
                    Divider(); stormCellsSection
                }
                if appState.showSurfaceObs {
                    Divider(); surfaceObsSection
                }
                Divider(); modelLayerSection
                Divider(); satelliteSection
                if !appState.placefiles.isEmpty {
                    Divider(); placefilesSection
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } label: {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("Data Summary").font(.caption.weight(.semibold))
                Spacer()
                if !appState.alerts.isEmpty { alertBadge }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.background.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weather data summary")
    }

    // MARK: - Radar

    private var paneSummarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Visible Panes", systemImage: "square.grid.2x2")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Active pane", selection: activePaneBinding) {
                ForEach(appState.visiblePanes) { pane in
                    Text(pane.displayName).tag(pane.id)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Active radar pane: \(appState.activePaneDisplayName)")
            .accessibilityHint("Selects which pane is described and controlled")

            ForEach(appState.visiblePanes) { pane in
                Button {
                    appState.selectPane(pane.id, announce: true)
                } label: {
                    HStack {
                        Text(pane.displayName + ":")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Text(paneAccessibilitySummary(pane))
                            .font(.caption.monospacedDigit())
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(pane.displayName): \(paneAccessibilitySummary(pane))")
                .accessibilityHint("Selects this pane for detailed radar data")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visible radar panes")
    }

    private var activePaneBinding: Binding<Int> {
        Binding(
            get: { appState.activePaneID },
            set: { appState.selectPane($0, announce: true) }
        )
    }

    private var radarSection: some View {
        let pane = appState.activePane
        return VStack(alignment: .leading, spacing: 4) {
            Label("\(pane.displayName) Radar", systemImage: "waveform.path.ecg")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let sweep = pane.currentSweep {
                Group {
                    dataRow(label: "Site",    value: sweep.site.displayName)
                    dataRow(label: "Product", value: pane.selectedProduct.displayName)
                    dataRow(label: "Tilt",    value: String(format: "%.1f°", sweep.elevationAngle))
                    dataRow(label: "Time",    value: sweep.scanTime.formatted(date: .abbreviated, time: .shortened) + " UTC")
                    dataRow(label: "VCP",     value: "\(sweep.vcpNumber)")
                    dataRow(label: "Gates",   value: "\(sweep.radials.first?.numGates ?? 0) at \(sweep.radials.first?.gateSizeMeters ?? 0) m spacing")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(pane.displayName) radar sweep details")
                Text(productLegendText(for: pane.selectedProduct))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Value scale: \(productLegendText(for: pane.selectedProduct))")
            } else if let l3 = pane.level3Sweep {
                Group {
                    dataRow(label: "Site",    value: l3.site.displayName)
                    dataRow(label: "Product", value: l3.productCode.displayName)
                    dataRow(label: "Time",    value: l3.scanTime.formatted(date: .abbreviated, time: .shortened) + " UTC")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(pane.displayName) Level 3 radar sweep details")
                Text(productLegendText(for: pane.selectedProduct))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Value scale: \(productLegendText(for: pane.selectedProduct))")
            } else if let error = pane.errorMessage {
                Text(error)
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("\(pane.displayName) error: \(error)")
            } else {
                Text(appState.isLoading || pane.isLoadingLevel3 ? "Loading radar data…" : "No radar data loaded.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func paneAccessibilitySummary(_ pane: RadarPaneState) -> String {
        if pane.isLoadingLevel3 { return "Loading \(pane.selectedProduct.displayName)" }
        if let error = pane.errorMessage { return "Error, \(error)" }
        if let sweep = pane.currentSweep {
            return "\(pane.selectedProduct.displayName), \(String(format: "%.1f", sweep.elevationAngle)) degrees, \(sweep.scanTime.formatted(date: .omitted, time: .shortened)) UTC"
        }
        if let l3 = pane.level3Sweep {
            return "\(l3.productCode.displayName), \(l3.scanTime.formatted(date: .omitted, time: .shortened)) UTC"
        }
        return "\(pane.selectedProduct.displayName), no data loaded"
    }

    private func productLegendText(for product: RadarProduct) -> String {
        switch product {
        case .reflectivity:
            return "5–20 dBZ: light precipitation. 35–50 dBZ: moderate to heavy rain. 55–65 dBZ: intense rain, possible large hail. 70+ dBZ: extreme — large hail likely."
        case .velocity:
            return "Negative values (red): moving toward radar. Positive values (green): moving away. Bright red and bright green near zero emphasize the inbound/outbound boundary; darker shades indicate stronger speeds. Values beyond ±27 m/s may be range-aliased."
        case .spectrumWidth:
            return "0–4 m/s: steady laminar flow. 8–13 m/s: turbulence or wind shear. >13 m/s: strong turbulence or rapidly changing winds."
        case .differentialReflectivity:
            return "< 0 dB: tumbling ice or hail. 0–1 dB: small raindrops or ice. 1–3 dB: rain. > 3 dB: large drops or wet hail coating."
        case .correlationCoefficient:
            return "High correlation coefficient values are red, indicating uniform meteorological targets. Values from 0.90 to 0.96 are yellow shades. Lower values shift through purple into blue, highlighting mixed targets, hail, debris, clutter, chaff, or biological echoes."
        case .differentialPhase:
            return "Increases monotonically through heavy rain. Used for attenuation correction and rain-rate estimation; best interpreted as a trend rather than absolute values."
        case .echoTops:
            return "Echo top height in thousands of feet. 30–40 kft: moderate convection. 40–55 kft: deep thunderstorm. > 55 kft: severe or supercell storm."
        case .vil:
            return "Vertically Integrated Liquid (kg/m²). Values below 1 are not drawn. > 30: heavy rain possible. > 50: hail possible. A sudden large drop in VIL may indicate hail descent."
        case .stormTotalPrecip, .oneHourPrecip:
            return "Estimated accumulated precipitation in inches. Accuracy decreases with distance from radar and in areas with beam blockage or bright-band contamination."
        }
    }

    // MARK: - Gate probe

    private func probeSection(_ result: ProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Gate Probe", systemImage: "scope")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(result.description)
                .font(.caption.monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            dataRow(label: "Bearing", value: String(format: "%.1f°", result.bearing))
            dataRow(label: "Range",   value: String(format: "%.0f km", result.rangeKm))
            Button("Clear probe") { appState.probeResult = nil }
                .font(.caption)
                .accessibilityLabel("Clear gate probe")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gate probe result: \(result.description)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Animation

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Loop Animation", systemImage: "film.stack")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.isLoadingAnimation {
                Text("Loading frames…").font(.caption).foregroundStyle(.secondary)
            } else if !appState.animationLevel3Frames.isEmpty {
                let sweep = appState.animationLevel3Frames[appState.animationFrameIndex]
                dataRow(label: "Frame",  value: "\(appState.animationFrameIndex + 1) of \(appState.animationLevel3Frames.count)")
                dataRow(label: "Time",   value: sweep.scanTime.formatted(date: .abbreviated, time: .shortened) + " UTC")
                dataRow(label: "Status", value: appState.isAnimating ? "Playing (\(appState.animationSpeed.displayName))" : "Paused")
                animationControls
            } else if !appState.animationFrames.isEmpty {
                let sweep = appState.animationFrames[appState.animationFrameIndex]
                dataRow(label: "Frame",  value: "\(appState.animationFrameIndex + 1) of \(appState.animationFrames.count)")
                dataRow(label: "Time",   value: sweep.scanTime.formatted(date: .abbreviated, time: .shortened) + " UTC")
                dataRow(label: "Status", value: appState.isAnimating ? "Playing (\(appState.animationSpeed.displayName))" : "Paused")
                animationControls
            } else {
                Text("No frames loaded.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel({
            if !appState.animationLevel3Frames.isEmpty {
                return "Loop animation: frame \(appState.animationFrameIndex + 1) of \(appState.animationLevel3Frames.count)"
            }
            return "Loop animation: frame \(appState.animationFrameIndex + 1) of \(appState.animationFrames.count)"
        }())
    }

    private var animationControls: some View {
        HStack(spacing: 8) {
            Button { appState.stepAnimation(by: -1) } label: { Label("Previous", systemImage: "backward.frame") }.font(.caption)
            Button { Task { await appState.toggleAnimation() } } label: {
                Label(appState.isAnimating ? "Stop" : "Play",
                      systemImage: appState.isAnimating ? "stop.fill" : "play.fill")
            }.font(.caption)
            Button { appState.stepAnimation(by: 1) } label: { Label("Next", systemImage: "forward.frame") }.font(.caption)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Animation playback controls")
    }

    // MARK: - Sonification

    private var sonificationSection: some View {
        @Bindable var state = appState
        return VStack(alignment: .leading, spacing: 6) {
            Label("Radar Sonification", systemImage: "waveform")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Text("Bearing:").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                Stepper(value: $state.sonificationBearing, in: 0...359, step: 5) {
                    Text(String(format: "%.0f°", appState.sonificationBearing)).font(.caption.monospacedDigit())
                }
                .accessibilityLabel("Bearing: \(Int(appState.sonificationBearing.rounded())) degrees")
                .accessibilityValue(String(format: "%.0f degrees", appState.sonificationBearing))
            }
            Button { appState.sonify() } label: {
                Label("Sonify Bearing", systemImage: "speaker.wave.2").font(.caption)
            }
            .disabled(appState.currentSweep == nil && appState.animationFrames.isEmpty)
            .accessibilityLabel("Sonify bearing \(Int(appState.sonificationBearing.rounded())) degrees")
            .accessibilityHint("Plays radar gate values along this bearing as audio tones. Higher pitch = stronger echo.")
            if !appState.sonificationResult.isEmpty {
                Text(appState.sonificationResult)
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityLabel("Sonification result: \(appState.sonificationResult)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Radar sonification")
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Active Alerts", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.alerts.isEmpty {
                Text("No active watches, warnings, or advisories.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(appState.alerts) { alert in alertRow(alert) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active weather alerts")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func alertRow(_ alert: NWSAlert) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(severityColor(alert.severity)).font(.caption)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.event).font(.caption.weight(.semibold))
                Text(alert.headline).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Text("Expires \(alert.expires.formatted(date: .omitted, time: .shortened)) UTC")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(alert.accessibilityLabel)
    }

    private var alertBadge: some View {
        Text("\(appState.alerts.count)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.red).foregroundStyle(.white)
            .clipShape(Capsule())
            .accessibilityLabel("\(appState.alerts.count) active alert\(appState.alerts.count == 1 ? "" : "s")")
    }

    // MARK: - SPC Outlooks

    private var outlooksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("SPC Convective Outlook", systemImage: "cloud.bolt.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.outlooks.isEmpty {
                Text("No outlook data loaded.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(appState.outlooks, id: \.day) { outlook in outlookRow(outlook) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SPC Convective Outlook")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func outlookRow(_ outlook: SPCOutlook) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "cloud.bolt").foregroundStyle(outlookColor(outlook.highestCategory))
                .font(.caption).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Day \(outlook.day) Outlook").font(.caption.weight(.semibold))
                if let highest = outlook.highestCategory {
                    Text("Highest risk: \(highest.displayName)").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("No severe weather areas").font(.caption2).foregroundStyle(.secondary)
                }
                Text("\(outlook.polygons.count) risk area\(outlook.polygons.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(outlookAccessibilityLabel(outlook))
    }

    private func outlookAccessibilityLabel(_ outlook: SPCOutlook) -> String {
        if let highest = outlook.highestCategory {
            return "Day \(outlook.day) outlook: highest risk \(highest.displayName), \(outlook.polygons.count) risk area\(outlook.polygons.count == 1 ? "" : "s")."
        }
        return "Day \(outlook.day) outlook: no severe weather areas."
    }

    private func outlookColor(_ category: SPCOutlook.Category?) -> Color {
        guard let category else { return .secondary }
        let c = category.color
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    // MARK: - Mesoscale Discussions

    private var mdSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Mesoscale Discussions", systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.mesoscaleDiscussions.isEmpty {
                Text("No active MDs.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(appState.mesoscaleDiscussions) { md in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MD #\(md.number)").font(.caption.weight(.semibold))
                        Text(md.concerning).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        Text("Expires \(md.expires.formatted(date: .omitted, time: .shortened)) UTC")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(md.accessibilityLabel)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SPC Mesoscale Discussions")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Storm Reports

    private var stormReportsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Storm Reports", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.stormReports.isEmpty {
                Text("No storm reports today.").font(.caption).foregroundStyle(.secondary)
            } else {
                let tornadoes = appState.stormReports.filter { if case .tornado = $0.kind { return true }; return false }
                let hail      = appState.stormReports.filter { if case .hail    = $0.kind { return true }; return false }
                let wind      = appState.stormReports.filter { if case .wind    = $0.kind { return true }; return false }
                dataRow(label: "Tornado", value: "\(tornadoes.count)")
                dataRow(label: "Hail",    value: "\(hail.count)")
                dataRow(label: "Wind",    value: "\(wind.count)")
                Text("Tap markers on map for details.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SPC storm reports: \(appState.stormReports.count) today")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Storm Cells

    private var stormCellsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Storm Cells", systemImage: "tornado")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.stormCells.isEmpty {
                Text("No storm cells identified by SCIT algorithm.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                dataRow(label: "Cells", value: "\(appState.stormCells.count) tracked")
                ForEach(appState.stormCells.prefix(5)) { cell in
                    Text(cell.accessibilityDescription)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if appState.stormCells.count > 5 {
                    Text("…and \(appState.stormCells.count - 5) more cells")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text("Tap cell markers on map for details.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storm cells: \(appState.stormCells.count) tracked by SCIT")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Surface Observations

    private var surfaceObsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Surface Observations", systemImage: "thermometer.sun")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.surfaceObs.isEmpty {
                Text("No surface obs loaded.").font(.caption).foregroundStyle(.secondary)
            } else {
                dataRow(label: "Stations", value: "\(appState.surfaceObs.count) nearby")
                let vfr  = appState.surfaceObs.filter { $0.flightCategory == .vfr  }.count
                let mvfr = appState.surfaceObs.filter { $0.flightCategory == .mvfr }.count
                let ifr  = appState.surfaceObs.filter { $0.flightCategory == .ifr  }.count
                let lifr = appState.surfaceObs.filter { $0.flightCategory == .lifr }.count
                if vfr  > 0 { dataRow(label: "VFR",  value: "\(vfr)") }
                if mvfr > 0 { dataRow(label: "MVFR", value: "\(mvfr)") }
                if ifr  > 0 { dataRow(label: "IFR",  value: "\(ifr)") }
                if lifr > 0 { dataRow(label: "LIFR", value: "\(lifr)") }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Surface observations: \(appState.surfaceObs.count) stations")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Model layer

    private var modelLayerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Model / Analysis Layer", systemImage: "chart.xyaxis.line")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.showModelLayer {
                dataRow(label: "Product", value: appState.modelProduct.displayName)
                if appState.modelProduct.supportsForecast {
                    dataRow(label: "Time", value: appState.modelForecastOffset.displayName)
                }
                Text(appState.modelProduct.accessibilityDescription)
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Model layer off. Enable with the Model toolbar button.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model analysis layer")
    }

    // MARK: - Satellite

    private var satelliteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("GOES Satellite", systemImage: "satellite")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if appState.showSatellite {
                dataRow(label: "Product", value: appState.satelliteProduct.displayName)
                Text(appState.satelliteProduct.accessibilityDescription)
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Satellite layer off. Enable with the Satellite toolbar button.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GOES satellite layer")
    }

    // MARK: - Placefiles

    private var placefilesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Placefiles", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(appState.placefiles) { placefile in placefileGroup(placefile) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Placefile overlays")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func placefileGroup(_ placefile: Placefile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(placefile.title).font(.caption.weight(.semibold))
            let points = placefile.items.filter { if case .point = $0.geometry { return true }; return false }
            if points.isEmpty {
                Text("\(placefile.items.count) feature\(placefile.items.count == 1 ? "" : "s") (no point labels)")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(points.prefix(10)) { item in
                    if !item.label.isEmpty {
                        Text(item.label).font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel(item.accessibilityLabel)
                    }
                }
                if points.count > 10 {
                    Text("…and \(points.count - 10) more").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Placefile \(placefile.title): \(placefile.items.count) features")
    }

    // MARK: - Helpers

    private func dataRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Text(value).font(.caption.monospacedDigit())
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
