import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            SiteSelectorView()
                .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    if appState.isLoading || appState.isLoadingLevel3 {
                        ProgressView().scaleEffect(0.7)
                    }
                    Text(appState.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Radar status: \(appState.statusDescription)")
                    Spacer()
                    if let error = appState.activePaneErrorMessage ?? appState.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(error)")
                    }
                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                    .accessibilityLabel("Refresh radar data")
                    .disabled(appState.isLoading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)

                // Map
                RadarPaneGrid()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // VoiceOver-first data panel
                AccessibilityPanel()
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    ArchiveDatePicker()
                    ScanTimePicker()
                    AnimationControls()
                    PaneLayoutPicker()
                    PaneSelector()
                    OverlaysPicker()
                    ModelLayerPicker()
                    SatellitePicker()
                    ProductPicker()
                    TiltPicker()
                }
            }
        }
        .sheet(isPresented: $state.showAbout) {
            AboutView()
        }
        .task {
            appState.requestNotificationPermission()
            await appState.refresh()
        }
    }
}

// MARK: - Radar panes

private struct RadarPaneGrid: View {
    @Environment(AppState.self) var appState

    var body: some View {
        Group {
            switch appState.paneLayout {
            case .single:
                if let pane = appState.visiblePanes.first {
                    RadarPaneView(paneID: pane.id)
                }
            case .two:
                HStack(spacing: 1) {
                    ForEach(appState.visiblePanes) { pane in
                        RadarPaneView(paneID: pane.id)
                    }
                }
            case .four:
                Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                    GridRow {
                        ForEach(appState.visiblePanes.prefix(2)) { pane in
                            RadarPaneView(paneID: pane.id)
                        }
                    }
                    GridRow {
                        ForEach(appState.visiblePanes.dropFirst(2).prefix(2)) { pane in
                            RadarPaneView(paneID: pane.id)
                        }
                    }
                }
            }
        }
        .background(.separator)
    }
}

private struct RadarPaneView: View {
    @Environment(AppState.self) var appState
    let paneID: Int

    private var isActive: Bool { appState.activePaneID == paneID }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MainMapView(paneID: paneID)
                .accessibilityHidden(true)  // map canvas; pane data stays in AccessibilityPanel

            VStack(spacing: 0) {
                paneHeader
                Spacer()
            }

            if let pane = appState.pane(id: paneID),
               pane.currentSweep != nil || (pane.level3Sweep != nil && pane.selectedProduct.isLevel3) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ColorScaleLegendView(product: pane.selectedProduct,
                                             palette: appState.colorPalette)
                            .padding(10)
                    }
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 3)
                .allowsHitTesting(false)
        }
        .background(.background)
    }

    private var paneHeader: some View {
        let pane = appState.pane(id: paneID)
        return HStack(spacing: 8) {
            Button {
                appState.selectPane(paneID, announce: true)
            } label: {
                Text(pane?.displayName ?? "Pane")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("\(pane?.displayName ?? "Pane")\(isActive ? ", active" : "")")
            .accessibilityHint("Selects this pane for toolbar product and tilt controls")

            Text(paneStatusText(pane))
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(pane?.errorMessage == nil ? Color.secondary : Color.red)
                .accessibilityLabel(paneStatusAccessibilityText(pane))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thinMaterial)
    }

    private func paneStatusText(_ pane: RadarPaneState?) -> String {
        guard let pane else { return "No pane" }
        if pane.isLoadingLevel3 { return "Loading \(pane.selectedProduct.displayName)..." }
        if let error = pane.errorMessage { return error }
        if let sweep = pane.currentSweep {
            return "\(pane.selectedProduct.displayName) \(String(format: "%.1f", sweep.elevationAngle)) deg \(sweep.scanTime.formatted(date: .omitted, time: .shortened))"
        }
        if let l3 = pane.level3Sweep {
            return "\(l3.productCode.displayName) \(l3.scanTime.formatted(date: .omitted, time: .shortened))"
        }
        return "\(pane.selectedProduct.displayName): no data"
    }

    private func paneStatusAccessibilityText(_ pane: RadarPaneState?) -> String {
        guard let pane else { return "Pane unavailable" }
        return "\(pane.displayName): \(paneStatusText(pane))"
    }
}

// MARK: - Overlays menu

private struct OverlaysPicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        Menu {
            Toggle("County Borders",        isOn: $state.showCountyBorders)
            Toggle("Range Rings",           isOn: $state.showRangeRings)
            Toggle("Alerts",                isOn: $state.showAlerts)
            Toggle("SPC Outlooks",          isOn: $state.showOutlooks)
            Divider()
            Toggle("Storm Reports",         isOn: $state.showStormReports)
            Toggle("Storm Cells",           isOn: $state.showStormCells)
            Toggle("Mesoscale Discussions", isOn: $state.showMesoscaleDiscussions)
            Divider()
            Toggle("Surface Observations",  isOn: $state.showSurfaceObs)
        } label: {
            Label("Overlays", systemImage: "map.fill")
        }
        .accessibilityLabel("Overlay layers menu")
    }
}

// MARK: - Toolbar pickers

private struct AnimationControls: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 4) {
            // Step back
            Button {
                appState.stepAnimation(by: -1)
            } label: {
                Image(systemName: "backward.frame")
            }
            .disabled(!appState.hasAnimationFrames)
            .accessibilityLabel("Previous frame")

            // Play / Stop
            Button {
                Task { await appState.toggleAnimation() }
            } label: {
                if appState.isLoadingAnimation {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: appState.isAnimating ? "stop.fill" : "play.fill")
                }
            }
            .accessibilityLabel(appState.isAnimating ? "Stop animation" : "Play loop animation")
            .disabled(appState.isLoadingAnimation)

            // Step forward
            Button {
                appState.stepAnimation(by: 1)
            } label: {
                Image(systemName: "forward.frame")
            }
            .disabled(!appState.hasAnimationFrames)
            .accessibilityLabel("Next frame")

            if appState.isAnimating || appState.hasAnimationFrames {
                Picker("Speed", selection: $state.animationSpeed) {
                    ForEach(AnimationSpeed.allCases) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .accessibilityLabel("Animation speed: \(appState.animationSpeed.displayName)")
            }
        }
    }
}

private struct PaneLayoutPicker: View {
    @Environment(AppState.self) var appState

    private var layoutBinding: Binding<RadarPaneLayout> {
        Binding(
            get: { appState.paneLayout },
            set: { appState.setPaneLayout($0) }
        )
    }

    var body: some View {
        Picker("Pane layout", selection: layoutBinding) {
            ForEach(RadarPaneLayout.allCases) { layout in
                Text(layout.displayName).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 170)
        .accessibilityLabel("Pane layout: \(appState.paneLayout.displayName)")
        .accessibilityHint("Changes the number of radar product panes shown visually")
    }
}

private struct PaneSelector: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(appState.visiblePanes) { pane in
                Button {
                    appState.selectPane(pane.id, announce: true)
                } label: {
                    Text("\(pane.id + 1)")
                        .font(.caption.weight(.semibold))
                        .frame(width: 20)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(pane.id + 1)")), modifiers: .command)
                .accessibilityLabel("\(pane.displayName)\(appState.activePaneID == pane.id ? ", active" : "")")
                .accessibilityHint("Selects the pane controlled by product and tilt menus")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active radar pane selector")
    }
}

private struct ModelLayerPicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 4) {
            Toggle(isOn: $state.showModelLayer) {
                Label("Model", systemImage: "chart.xyaxis.line")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Model layer: \(appState.showModelLayer ? "on" : "off")")

            if appState.showModelLayer {
                Picker("Model product", selection: $state.modelProduct) {
                    ForEach(ModelProduct.allCases) { product in
                        Text(product.displayName).tag(product)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .accessibilityLabel("Model product: \(appState.modelProduct.displayName)")

                if appState.modelProduct.supportsForecast {
                    Picker("Forecast time", selection: $state.modelForecastOffset) {
                        ForEach(ModelForecastOffset.allCases) { offset in
                            Text(offset.displayName).tag(offset)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .accessibilityLabel("Forecast time: \(appState.modelForecastOffset.displayName)")
                }
            }
        }
    }
}

private struct SatellitePicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 4) {
            Toggle(isOn: $state.showSatellite) {
                Label("Satellite", systemImage: "satellite")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Satellite layer: \(appState.showSatellite ? "on" : "off")")

            if appState.showSatellite {
                Picker("Satellite product", selection: $state.satelliteProduct) {
                    ForEach(GOESSatelliteProduct.allCases) { product in
                        Text(product.displayName).tag(product)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .accessibilityLabel("Satellite product: \(appState.satelliteProduct.displayName)")
            }
        }
    }
}

private struct ProductPicker: View {
    @Environment(AppState.self) var appState

    private var productBinding: Binding<RadarProduct> {
        Binding(
            get: { appState.selectedProduct },
            set: { appState.setProduct($0) }
        )
    }

    var body: some View {
        Picker("Product", selection: productBinding) {
            Section("Level 2") {
                ForEach(RadarProduct.allCases.filter { !$0.isLevel3 }) { product in
                    Text(product.displayName).tag(product)
                }
            }
            Section("Level 3") {
                ForEach(RadarProduct.allCases.filter { $0.isLevel3 }) { product in
                    Text(product.displayName).tag(product)
                }
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("\(appState.activePaneDisplayName) radar product: \(appState.selectedProduct.displayName)")
        .frame(width: 170)
    }
}

private struct TiltPicker: View {
    @Environment(AppState.self) var appState

    private let tilts = ["0.5°", "1.5°", "2.4°", "3.4°", "4.3°"]

    private var tiltBinding: Binding<Int> {
        Binding(
            get: { appState.tiltIndex },
            set: { appState.setTiltIndex($0) }
        )
    }

    var body: some View {
        Picker("Tilt", selection: tiltBinding) {
            ForEach(tilts.indices, id: \.self) { i in
                Text(tilts[i]).tag(i)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("\(appState.activePaneDisplayName) elevation tilt: \(tilts[appState.tiltIndex])")
        .frame(width: 80)
        .disabled(appState.selectedProduct.isLevel3)
    }
}

// MARK: - Archive date + scan time controls

private struct ArchiveDatePicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        DatePicker(
            "Date",
            selection: $state.selectedDate,
            in: ...Date.now,
            displayedComponents: .date
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(width: 115)
        .accessibilityLabel("Archive date: \(appState.selectedDate.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint("Change to load scans for a different date")
        .onChange(of: appState.selectedDate) { _, _ in
            Task { await appState.refresh() }
        }
    }
}

private struct ScanTimePicker: View {
    @Environment(AppState.self) var appState

    // Custom binding: reading uses selectedScan for display; writing calls loadScan
    // so the Picker's set-side (user action only) triggers the actual download
    // without the double-load that onChange would cause when refresh() sets selectedScan.
    private var scanBinding: Binding<ScanEntry?> {
        Binding(
            get: { appState.selectedScan },
            set: { newScan in
                guard let scan = newScan else { return }
                Task { await appState.loadScan(scan) }
            }
        )
    }

    var body: some View {
        Picker("Scan time", selection: scanBinding) {
            ForEach(appState.availableScans) { scan in
                Text(scan.scanTime.formatted(date: .omitted, time: .shortened) + " UTC")
                    .tag(Optional(scan))
            }
        }
        .pickerStyle(.menu)
        .frame(width: 110)
        .disabled(appState.isLoading || appState.availableScans.isEmpty)
        .accessibilityLabel("Scan time: \(appState.selectedScan.map { $0.scanTime.formatted(date: .omitted, time: .shortened) + " UTC" } ?? "none")")
        .accessibilityHint("Select a scan time to load")
    }
}
