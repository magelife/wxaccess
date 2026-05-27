import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import AppKit

enum RadarPaneLayout: Int, CaseIterable, Identifiable {
    case single = 1
    case two = 2
    case four = 4

    var id: Int { rawValue }
    var paneCount: Int { rawValue }

    var displayName: String {
        switch self {
        case .single: "Single"
        case .two: "Two"
        case .four: "Four"
        }
    }
}

struct RadarPaneState: Identifiable {
    let id: Int
    var selectedProduct: RadarProduct
    var tiltIndex: Int
    var currentSweep: RadarSweep?
    var level3Sweep: Level3RadialSweep?
    var isLoadingLevel3: Bool
    var errorMessage: String?
    var probeResult: ProbeResult?

    var displayName: String { "Pane \(id + 1)" }

    static let defaults: [RadarPaneState] = [
        RadarPaneState(id: 0, selectedProduct: .reflectivity, tiltIndex: 0),
        RadarPaneState(id: 1, selectedProduct: .velocity, tiltIndex: 0),
        RadarPaneState(id: 2, selectedProduct: .correlationCoefficient, tiltIndex: 0),
        RadarPaneState(id: 3, selectedProduct: .stormTotalPrecip, tiltIndex: 0),
    ]

    init(id: Int,
         selectedProduct: RadarProduct,
         tiltIndex: Int = 0,
         currentSweep: RadarSweep? = nil,
         level3Sweep: Level3RadialSweep? = nil,
         isLoadingLevel3: Bool = false,
         errorMessage: String? = nil,
         probeResult: ProbeResult? = nil) {
        self.id = id
        self.selectedProduct = selectedProduct
        self.tiltIndex = tiltIndex
        self.currentSweep = currentSweep
        self.level3Sweep = level3Sweep
        self.isLoadingLevel3 = isLoadingLevel3
        self.errorMessage = errorMessage
        self.probeResult = probeResult
    }
}

@Observable
@MainActor
final class AppState: NSObject {
    var selectedSite: NEXRADSite = NEXRADSiteCatalog.site(icao: "KEWX") ?? NEXRADSiteCatalog.all[0]
    var paneLayout: RadarPaneLayout = .single
    var activePaneID: Int = 0
    var radarPanes: [RadarPaneState] = RadarPaneState.defaults
    var sharedMapRegion: MKCoordinateRegion?
    var availableScans: [ScanEntry] = []
    var selectedScan: ScanEntry?
    var alerts: [NWSAlert] = []
    var outlooks: [SPCOutlook] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var showAbout: Bool = false
    var showSatellite: Bool = false
    var satelliteProduct: GOESSatelliteProduct = .infrared
    var showModelLayer: Bool = false
    var modelProduct: ModelProduct = .mrmsSeamlessHSR
    var modelForecastOffset: ModelForecastOffset = .now
    var placefileURLs: [URL] = []
    var placefiles: [Placefile] = []

    // MARK: - Archive date
    var selectedDate: Date = .now

    // MARK: - New overlay state
    var stormReports: [SPCStormReport] = []
    var mesoscaleDiscussions: [SPCMesoscaleDiscussion] = []
    var surfaceObs: [SurfaceObs] = []
    var showStormReports: Bool = false
    var showMesoscaleDiscussions: Bool = false
    var showSurfaceObs: Bool = false
    var showCountyBorders: Bool = false
    var showRangeRings: Bool = false
    var showAlerts: Bool = false
    var showOutlooks: Bool = false
    var colorPalette: ColorPalette = .nwsStandard

    // MARK: - Storm cell tracking (SCIT / NST)
    var stormCells: [StormCell] = []
    var showStormCells: Bool = false

    // MARK: - Animation
    var isAnimating: Bool = false
    var animationFrames: [RadarSweep] = []
    var animationLevel3Frames: [Level3RadialSweep] = []
    var animationFrameIndex: Int = 0
    var animationSpeed: AnimationSpeed = .normal
    var isLoadingAnimation: Bool = false
    private var animationTask: Task<Void, Never>?

    var hasAnimationFrames: Bool { !animationFrames.isEmpty || !animationLevel3Frames.isEmpty }

    // MARK: - Sonification
    var sonificationBearing: Double = 0
    var sonificationResult: String = ""

    // MARK: - Auto-refresh
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - Notifications
    private var notifiedAlertIDs: Set<String> = []

    private var allSweeps: [RadarSweep] = []

    // MARK: - Location
    private var locationManager: CLLocationManager?
    var isLocating: Bool = false

    var visiblePanes: [RadarPaneState] {
        Array(radarPanes.prefix(paneLayout.paneCount))
    }

    var activePane: RadarPaneState {
        radarPanes.first { $0.id == activePaneID } ?? radarPanes[0]
    }

    var activePaneDisplayName: String { activePane.displayName }

    var isLoadingLevel3: Bool {
        visiblePanes.contains { $0.isLoadingLevel3 }
    }

    var selectedProduct: RadarProduct {
        get { activePane.selectedProduct }
        set { setProduct(newValue, forPane: activePaneID) }
    }

    var currentSweep: RadarSweep? {
        get { activePane.currentSweep }
        set { updatePane(activePaneID) { $0.currentSweep = newValue } }
    }

    var level3Sweep: Level3RadialSweep? {
        get { activePane.level3Sweep }
        set { updatePane(activePaneID) { $0.level3Sweep = newValue } }
    }

    var tiltIndex: Int {
        get { activePane.tiltIndex }
        set { setTiltIndex(newValue, forPane: activePaneID) }
    }

    var probeResult: ProbeResult? {
        get { activePane.probeResult }
        set { updatePane(activePaneID) { $0.probeResult = newValue } }
    }

    var activePaneErrorMessage: String? { activePane.errorMessage }

    var statusDescription: String {
        if isLoading || isLoadingAnimation || isLoadingLevel3 { return "Loading…" }
        let pane = activePane
        if let error = pane.errorMessage {
            return "\(pane.displayName) error: \(error)"
        }
        if let l3 = pane.level3Sweep, pane.selectedProduct.isLevel3 {
            return "\(pane.displayName): \(l3.site.icao) \(l3.productCode.displayName) — \(l3.scanTime.formatted(date: .omitted, time: .shortened)) UTC"
        }
        if isAnimating, !animationLevel3Frames.isEmpty {
            let sweep = animationLevel3Frames[animationFrameIndex]
            let frame = "\(animationFrameIndex + 1)/\(animationLevel3Frames.count)"
            return "\(sweep.site.icao) \(sweep.productCode.displayName) — frame \(frame) \(sweep.scanTime.formatted(date: .omitted, time: .shortened)) UTC"
        }
        if isAnimating, !animationFrames.isEmpty {
            let sweep = animationFrames[animationFrameIndex]
            let frame = "\(animationFrameIndex + 1)/\(animationFrames.count)"
            return "\(sweep.site.icao) \(selectedProduct.displayName) \(String(format: "%.1f", sweep.elevationAngle))° — frame \(frame) \(sweep.scanTime.formatted(date: .omitted, time: .shortened)) UTC"
        }
        if let sweep = pane.currentSweep {
            return "\(pane.displayName): \(sweep.site.icao) \(pane.selectedProduct.displayName) \(String(format: "%.1f", sweep.elevationAngle))° — \(sweep.scanTime.formatted(date: .omitted, time: .shortened))"
        }
        return "No data loaded"
    }

    // MARK: - Pane management

    func pane(id: Int) -> RadarPaneState? {
        radarPanes.first { $0.id == id }
    }

    func selectPane(_ id: Int, announce: Bool = false) {
        guard visiblePanes.contains(where: { $0.id == id }) else { return }
        activePaneID = id
        if announce, let pane = pane(id: id) {
            NSAccessibility.post(
                element: NSApp as AnyObject,
                notification: .announcementRequested,
                userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: "\(pane.displayName) selected"]
            )
        }
    }

    func setPaneLayout(_ layout: RadarPaneLayout) {
        paneLayout = layout
        if !visiblePanes.contains(where: { $0.id == activePaneID }) {
            activePaneID = 0
        }
        for pane in visiblePanes where pane.selectedProduct.isLevel3 && pane.level3Sweep == nil && !pane.isLoadingLevel3 {
            Task { await loadLevel3Product(pane.selectedProduct, paneID: pane.id) }
        }
    }

    func defaultMapRegion() -> MKCoordinateRegion {
        MKCoordinateRegion(center: selectedSite.coordinate,
                           latitudinalMeters: 800_000,
                           longitudinalMeters: 800_000)
    }

    func updateSharedMapRegion(_ region: MKCoordinateRegion) {
        sharedMapRegion = region
    }

    func setProduct(_ product: RadarProduct, forPane paneID: Int? = nil) {
        let id = paneID ?? activePaneID
        clearAnimationFrames()
        updatePane(id) { pane in
            pane.selectedProduct = product
            pane.errorMessage = nil
            pane.probeResult = nil
            pane.isLoadingLevel3 = false
            if product.isLevel3 {
                pane.currentSweep = nil
                pane.level3Sweep = nil
            } else {
                pane.level3Sweep = nil
            }
        }
        if product.isLevel3 {
            Task { await loadLevel3Product(product, paneID: id) }
        } else {
            selectCurrentSweep(paneID: id)
        }
    }

    func setTiltIndex(_ index: Int, forPane paneID: Int? = nil) {
        let id = paneID ?? activePaneID
        updatePane(id) { $0.tiltIndex = index }
        selectCurrentSweep(paneID: id)
    }

    private func updatePane(_ id: Int, _ update: (inout RadarPaneState) -> Void) {
        guard let idx = radarPanes.firstIndex(where: { $0.id == id }) else { return }
        update(&radarPanes[idx])
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        errorMessage = nil
        for pane in visiblePanes where pane.selectedProduct.isLevel3 {
            updatePane(pane.id) {
                $0.level3Sweep = nil
                $0.errorMessage = nil
            }
        }
        do {
            async let scans    = Level2Fetcher.shared.listScans(site: selectedSite, date: selectedDate)
            async let alerts   = AlertsFetcher.shared.fetchAlerts(near: selectedSite.coordinate)
            async let outlooks = SPCOutlookFetcher.shared.fetchOutlooks()
            async let mds      = SPCMesoscaleDiscussionFetcher.shared.fetchDiscussions()
            async let reports  = SPCStormReportFetcher.shared.fetchReports()
            async let obs      = SurfaceObsFetcher.shared.fetchObs(near: selectedSite)
            async let pfiles   = PlacefileFetcher.shared.refresh(existing: placefiles, urls: placefileURLs)
            async let cells    = SCITFetcher.shared.fetchLatest(site: selectedSite)

            availableScans = try await scans
            if let latest = availableScans.first {
                await loadScan(latest)
            }
            await reloadVisibleLevel3Panes()
            self.alerts                = try await alerts
            self.outlooks              = await outlooks
            self.mesoscaleDiscussions  = await mds
            self.stormReports          = await reports
            self.surfaceObs            = await obs
            self.placefiles            = await pfiles
            self.stormCells            = (try? await cells) ?? []

            notifyNewAlerts(self.alerts)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        scheduleAutoRefresh()
    }

    func loadScan(_ entry: ScanEntry) async {
        selectedScan = entry
        isLoading = true
        errorMessage = nil
        do {
            let data = try await Level2Fetcher.shared.download(entry: entry)
            allSweeps = try Level2Decoder().decode(data: data)
            selectCurrentSweepForLevel2Panes()
            if let sweep = activePane.currentSweep {
                let msg = "Radar loaded: \(activePane.displayName), \(sweep.site.displayName), \(activePane.selectedProduct.displayName)"
                NSAccessibility.post(element: NSApp as AnyObject, notification: .announcementRequested,
                                     userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: msg])
            }
        } catch {
            errorMessage = error.localizedDescription
            NSAccessibility.post(element: NSApp as AnyObject, notification: .announcementRequested,
                                 userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: "Failed to load radar data: \(error.localizedDescription)"])
        }
        isLoading = false
    }

    func selectCurrentSweep() {
        selectCurrentSweep(paneID: activePaneID)
    }

    func selectCurrentSweep(paneID: Int) {
        guard let pane = pane(id: paneID), !pane.selectedProduct.isLevel3 else { return }
        let target = tiltAngle(for: pane.tiltIndex)
        let product = pane.selectedProduct.rawValue
        let sweep = Self.bestSweep(in: allSweeps, product: product, targetElevation: target)
        updatePane(paneID) { $0.currentSweep = sweep }
    }

    private func selectCurrentSweepForLevel2Panes() {
        for pane in radarPanes where !pane.selectedProduct.isLevel3 {
            selectCurrentSweep(paneID: pane.id)
        }
    }

    nonisolated static func bestSweep(in sweeps: [RadarSweep], product: String, targetElevation: Double) -> RadarSweep? {
        let productSweeps = sweeps.filter { $0.momentType == product }
        return bestSweep(in: productSweeps, targetElevation: targetElevation)
            ?? bestSweep(in: sweeps, targetElevation: targetElevation)
    }

    private nonisolated static func bestSweep(in sweeps: [RadarSweep], targetElevation: Double) -> RadarSweep? {
        let nearby = sweeps.filter { abs($0.elevationAngle - targetElevation) <= 0.6 }
        let candidates = nearby.isEmpty ? sweeps : nearby
        return candidates.max { lhs, rhs in
            let lhsCoverage = azimuthCoverageScore(lhs)
            let rhsCoverage = azimuthCoverageScore(rhs)
            if lhsCoverage != rhsCoverage {
                return lhsCoverage < rhsCoverage
            }
            return abs(lhs.elevationAngle - targetElevation) > abs(rhs.elevationAngle - targetElevation)
        }
    }

    private nonisolated static func azimuthCoverageScore(_ sweep: RadarSweep) -> Int {
        Set(sweep.radials.map { Int(($0.azimuth * 2).rounded()) % 720 }).count
    }

    // MARK: - Level 3 products

    func loadLevel3Product(_ product: RadarProduct, paneID: Int? = nil) async {
        let id = paneID ?? activePaneID
        guard let code = product.level3ProductCode else { return }
        let site = selectedSite
        updatePane(id) {
            $0.isLoadingLevel3 = true
            $0.errorMessage = nil
            $0.currentSweep = nil
        }
        errorMessage = nil
        do {
            let entries = try await Level3Fetcher.shared.listScans(site: site,
                                                                    product: code, limit: 1)
            guard let entry = entries.first else {
                throw URLError(.fileDoesNotExist)
            }
            let data   = try await Level3Fetcher.shared.download(entry: entry)
            let sweep = try Level3Decoder().decode(data: data, site: site, product: code)
            guard isCurrentLevel3Request(paneID: id, product: product, site: site) else { return }
            updatePane(id) {
                $0.level3Sweep = sweep
                $0.errorMessage = nil
            }
            if let pane = pane(id: id) {
                NSAccessibility.post(
                    element: NSApp as AnyObject,
                    notification: .announcementRequested,
                    userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: "\(pane.displayName) loaded \(code.displayName) for \(site.icao)."]
                )
            }
        } catch {
            guard isCurrentLevel3Request(paneID: id, product: product, site: site) else { return }
            updatePane(id) {
                $0.errorMessage = error.localizedDescription
                $0.level3Sweep = nil
            }
            errorMessage = error.localizedDescription
        }
        if isCurrentLevel3Request(paneID: id, product: product, site: site) {
            updatePane(id) { $0.isLoadingLevel3 = false }
        }
    }

    private func isCurrentLevel3Request(paneID: Int, product: RadarProduct, site: NEXRADSite) -> Bool {
        pane(id: paneID)?.selectedProduct == product && selectedSite.id == site.id
    }

    private func reloadVisibleLevel3Panes() async {
        for pane in visiblePanes where pane.selectedProduct.isLevel3 {
            await loadLevel3Product(pane.selectedProduct, paneID: pane.id)
        }
    }

    // MARK: - Animation

    func toggleAnimation() async {
        if isAnimating { stopAnimation() } else { await startAnimation() }
    }

    func startAnimation() async {
        if selectedProduct.isLevel3 {
            if animationLevel3Frames.isEmpty { await loadLevel3AnimationFrames() }
            guard !animationLevel3Frames.isEmpty else { return }
            isAnimating = true
            animationTask?.cancel()
            animationTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let next = (self.animationFrameIndex + 1) % self.animationLevel3Frames.count
                    self.animationFrameIndex = next
                    self.level3Sweep = self.animationLevel3Frames[next]
                    self.announceAnimationFrameL3(index: next, total: self.animationLevel3Frames.count,
                                                  sweep: self.animationLevel3Frames[next])
                    try? await Task.sleep(nanoseconds: UInt64(self.animationSpeed.interval * 1_000_000_000))
                }
            }
        } else {
            if animationFrames.isEmpty { await loadAnimationFrames() }
            guard !animationFrames.isEmpty else { return }
            isAnimating = true
            animationTask?.cancel()
            animationTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let next = (self.animationFrameIndex + 1) % self.animationFrames.count
                    self.animationFrameIndex = next
                    self.currentSweep = self.animationFrames[next]
                    self.announceAnimationFrame(index: next, total: self.animationFrames.count,
                                                sweep: self.animationFrames[next])
                    try? await Task.sleep(nanoseconds: UInt64(self.animationSpeed.interval * 1_000_000_000))
                }
            }
        }
    }

    func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        isAnimating = false
        if selectedProduct.isLevel3 {
            // level3Sweep is already the last-displayed frame; leave it.
        } else {
            selectCurrentSweep()
        }
    }

    func stepAnimation(by delta: Int) {
        if selectedProduct.isLevel3, !animationLevel3Frames.isEmpty {
            animationFrameIndex = (animationFrameIndex + delta + animationLevel3Frames.count) % animationLevel3Frames.count
            level3Sweep = animationLevel3Frames[animationFrameIndex]
        } else if !animationFrames.isEmpty {
            animationFrameIndex = (animationFrameIndex + delta + animationFrames.count) % animationFrames.count
            currentSweep = animationFrames[animationFrameIndex]
        }
    }

    func clearAnimationFrames() {
        if isAnimating { stopAnimation() }
        animationFrames = []
        animationLevel3Frames = []
        animationFrameIndex = 0
    }

    private func loadAnimationFrames() async {
        isLoadingAnimation = true
        errorMessage = nil
        do {
            let scans   = try await Level2Fetcher.shared.listScans(site: selectedSite)
            let recent  = Array(scans.prefix(10).reversed())
            let product = selectedProduct.rawValue
            let target  = tiltAngle(for: tiltIndex)

            var ordered: [(Int, RadarSweep)] = []
            await withTaskGroup(of: (Int, RadarSweep?).self) { group in
                for (idx, scan) in recent.enumerated() {
                    group.addTask {
                        guard let data = try? await Level2Fetcher.shared.download(entry: scan) else { return (idx, nil) }
                        let sweeps = (try? Level2Decoder().decode(data: data)) ?? []
                        let sweep = AppState.bestSweep(in: sweeps, product: product, targetElevation: target)
                        return (idx, sweep)
                    }
                }
                for await result in group {
                    if let sweep = result.1 { ordered.append((result.0, sweep)) }
                }
            }
            animationFrames     = ordered.sorted { $0.0 < $1.0 }.map { $0.1 }
            animationFrameIndex = max(0, animationFrames.count - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingAnimation = false
    }

    private func loadLevel3AnimationFrames() async {
        guard let code = selectedProduct.level3ProductCode else { return }
        isLoadingAnimation = true
        errorMessage = nil
        do {
            let entries = try await Level3Fetcher.shared.listScans(site: selectedSite, product: code, limit: 10)
            let recent  = Array(entries.prefix(10).reversed())
            let site    = selectedSite

            var ordered: [(Int, Level3RadialSweep)] = []
            await withTaskGroup(of: (Int, Level3RadialSweep?).self) { group in
                for (idx, entry) in recent.enumerated() {
                    group.addTask {
                        guard let data = try? await Level3Fetcher.shared.download(entry: entry) else { return (idx, nil) }
                        let sweep = try? Level3Decoder().decode(data: data, site: site, product: code)
                        return (idx, sweep)
                    }
                }
                for await result in group {
                    if let sweep = result.1 { ordered.append((result.0, sweep)) }
                }
            }
            animationLevel3Frames = ordered.sorted { $0.0 < $1.0 }.map { $0.1 }
            animationFrameIndex   = max(0, animationLevel3Frames.count - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingAnimation = false
    }

    // MARK: - Sonification

    func sonify() {
        guard let sweep = currentSweep ?? animationFrames.last else {
            sonificationResult = "No radar data to sonify."
            return
        }
        sonificationResult = SonificationEngine.shared.sonify(sweep: sweep, bearing: sonificationBearing)
    }

    // MARK: - Gate probe

    func probe(at coordinate: CLLocationCoordinate2D) {
        probe(at: coordinate, paneID: activePaneID)
    }

    func probe(at coordinate: CLLocationCoordinate2D, paneID: Int) {
        guard let pane = pane(id: paneID) else { return }
        let siteCoord: CLLocationCoordinate2D
        if let sweep = pane.currentSweep {
            siteCoord = sweep.site.coordinate
        } else if let l3 = pane.level3Sweep {
            siteCoord = l3.site.coordinate
        } else {
            updatePane(paneID) {
                $0.probeResult = ProbeResult(coordinate: coordinate, bearing: 0, rangeKm: 0,
                                             description: "No radar data loaded.")
            }
            return
        }

        let (bearing, rangeKm) = bearingAndRangeKm(from: siteCoord, to: coordinate)
        let cp = compassPoint(bearing)

        if let sweep = pane.currentSweep, !sweep.radials.isEmpty {
            let rangeM = rangeKm * 1000
            guard let radial = sweep.radials.min(by: {
                angularDiff($0.azimuth, bearing) < angularDiff($1.azimuth, bearing)
            }) else { return }

            let gateIdx = Int(round((rangeM - Double(radial.firstGateMeters)) / Double(radial.gateSizeMeters)))
            let loc = "\(cp) \(String(format: "%.0f", rangeKm)) km from \(sweep.site.icao)"

            if gateIdx < 0 || gateIdx >= radial.numGates {
                let desc = "Outside radar coverage — \(loc)"
                updatePane(paneID) {
                    $0.probeResult = ProbeResult(coordinate: coordinate, bearing: bearing, rangeKm: rangeKm, description: desc)
                }
                announceProbe("\(pane.displayName): \(desc)")
                return
            }
            let phys = radial.physicalValue(gateIndex: gateIdx)
            let valStr = phys.map { String(format: "%.1f \(momentUnit(sweep.momentType))", $0) } ?? "No echo"
            let desc = "\(momentLabel(sweep.momentType)): \(valStr), \(loc)"
            updatePane(paneID) {
                $0.probeResult = ProbeResult(coordinate: coordinate, bearing: bearing, rangeKm: rangeKm, description: desc)
            }
            announceProbe("\(pane.displayName): \(desc)")
            return
        }

        if let l3 = pane.level3Sweep, !l3.radials.isEmpty {
            guard let radial = l3.radials.min(by: {
                angularDiff($0.startAngle, bearing) < angularDiff($1.startAngle, bearing)
            }) else { return }

            let binIdx = Int((rangeKm - l3.firstBinKm) / l3.binSizeKm)
            let loc = "\(cp) \(String(format: "%.0f", rangeKm)) km from \(l3.site.icao)"

            if binIdx < 0 || binIdx >= radial.data.count {
                let desc = "Outside radar coverage — \(loc)"
                updatePane(paneID) {
                    $0.probeResult = ProbeResult(coordinate: coordinate, bearing: bearing, rangeKm: rangeKm, description: desc)
                }
                announceProbe("\(pane.displayName): \(desc)")
                return
            }
            let phys = l3.productCode.physicalValue(code: radial.data[binIdx])
            let valStr = phys.map { String(format: "%.1f \(l3.productCode.physicalUnit)", $0) } ?? "No echo"
            let desc = "\(l3.productCode.displayName): \(valStr), \(loc)"
            updatePane(paneID) {
                $0.probeResult = ProbeResult(coordinate: coordinate, bearing: bearing, rangeKm: rangeKm, description: desc)
            }
            announceProbe("\(pane.displayName): \(desc)")
        }
    }

    private func announceProbe(_ text: String) {
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: text]
        )
    }

    private func bearingAndRangeKm(from site: CLLocationCoordinate2D,
                                    to pt: CLLocationCoordinate2D) -> (Double, Double) {
        let lat1 = site.latitude  * .pi / 180
        let lat2 = pt.latitude    * .pi / 180
        let dLon = (pt.longitude - site.longitude) * .pi / 180
        let dLat = (pt.latitude  - site.latitude)  * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let R = 6371.0
        let a = sin(dLat/2)*sin(dLat/2) + cos(lat1)*cos(lat2)*sin(dLon/2)*sin(dLon/2)
        return (bearing, R * 2 * atan2(sqrt(a), sqrt(1 - a)))
    }

    private func angularDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private func compassPoint(_ b: Double) -> String {
        let d = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return d[Int((b + 11.25) / 22.5) % 16]
    }

    private func momentLabel(_ t: String) -> String {
        switch t {
        case "REF": return "Reflectivity"
        case "VEL": return "Velocity"
        case "SW":  return "Spectrum Width"
        case "ZDR": return "Diff. Reflectivity"
        case "PHI": return "Diff. Phase"
        case "RHO": return "Corr. Coefficient"
        default:    return t
        }
    }

    private func momentUnit(_ t: String) -> String {
        switch t {
        case "REF":       return "dBZ"
        case "VEL", "SW": return "m/s"
        case "ZDR":       return "dB"
        case "PHI":       return "°"
        default:          return ""
        }
    }

    // MARK: - Auto-refresh

    private func scheduleAutoRefresh() {
        autoRefreshTask?.cancel()
        guard UserDefaults.standard.bool(forKey: "autoRefresh") else { return }
        let mins    = UserDefaults.standard.double(forKey: "refreshInterval")
        let seconds = mins > 0 ? mins * 60 : 5 * 60
        autoRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - VoiceOver frame announcements

    private func announceAnimationFrame(index: Int, total: Int, sweep: RadarSweep) {
        let timeStr = sweep.scanTime.formatted(date: .omitted, time: .shortened)
        let text    = "Frame \(index + 1) of \(total), \(timeStr) UTC"
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: text]
        )
    }

    private func announceAnimationFrameL3(index: Int, total: Int, sweep: Level3RadialSweep) {
        let timeStr = sweep.scanTime.formatted(date: .omitted, time: .shortened)
        let text    = "Frame \(index + 1) of \(total), \(timeStr) UTC"
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: text]
        )
    }

    // MARK: - Alert notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyNewAlerts(_ newAlerts: [NWSAlert]) {
        let highPriority = newAlerts.filter {
            $0.kind == .tornadoWarning || $0.kind == .severeThunderstormWarning
        }
        for alert in highPriority where !notifiedAlertIDs.contains(alert.id) {
            notifiedAlertIDs.insert(alert.id)
            let content       = UNMutableNotificationContent()
            content.title     = alert.event
            content.body      = alert.headline
            content.sound     = .default
            let request       = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Auto-location

    func selectNearestSite() {
        isLocating = true
        let mgr = CLLocationManager()
        locationManager = mgr
        mgr.delegate = self
        switch mgr.authorizationStatus {
        case .notDetermined:
            mgr.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            mgr.requestLocation()
        default:
            isLocating = false
            errorMessage = "Location access denied. Change in System Settings → Privacy."
        }
    }

    private func didReceiveLocation(_ coordinate: CLLocationCoordinate2D) {
        let nearest = NEXRADSiteCatalog.all.min { a, b in
            haversineKm(a.coordinate, coordinate) < haversineKm(b.coordinate, coordinate)
        }
        if let site = nearest {
            selectedSite = site
            updateSharedMapRegion(defaultMapRegion())
            Task { await refresh() }
        }
        isLocating = false
    }

    private func haversineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R    = 6371.0
        let dLat = (b.latitude  - a.latitude)  * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let sinLat = sin(dLat / 2), sinLon = sin(dLon / 2)
        let h = sinLat * sinLat + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sinLon * sinLon
        return R * 2 * asin(sqrt(h))
    }

    // MARK: - Helpers

    private func tiltAngle(for index: Int) -> Double {
        let tilts: [Double] = [0.5, 1.45, 2.4, 3.35, 4.3]
        return index < tilts.count ? tilts[index] : tilts[0]
    }
}

// MARK: - CLLocationManagerDelegate

extension AppState: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.first?.coordinate else { return }
        Task { @MainActor in self.didReceiveLocation(coord) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "Location failed: \(error.localizedDescription)"
            self.isLocating = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorized:
                self.locationManager?.requestLocation()
            case .denied, .restricted:
                self.errorMessage = "Location access denied."
                self.isLocating = false
            default: break
            }
        }
    }
}

// MARK: - Supporting enums

enum RadarProduct: String, CaseIterable, Identifiable {
    // Level 2 moment products
    case reflectivity             = "REF"
    case velocity                 = "VEL"
    case spectrumWidth            = "SW"
    case differentialReflectivity = "ZDR"
    case correlationCoefficient   = "RHO"
    case differentialPhase        = "PHI"
    // Level 3-only composite/derived products
    case echoTops                 = "EET"
    case vil                      = "DVL"
    case stormTotalPrecip         = "STP"
    case oneHourPrecip            = "OHP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reflectivity:             "Reflectivity"
        case .velocity:                 "Velocity"
        case .spectrumWidth:            "Spectrum Width"
        case .differentialReflectivity: "Diff. Reflectivity"
        case .correlationCoefficient:   "Corr. Coefficient"
        case .differentialPhase:        "Diff. Phase"
        case .echoTops:                 "Echo Tops"
        case .vil:                      "Digital VIL"
        case .stormTotalPrecip:         "Storm Total Precip"
        case .oneHourPrecip:            "1-Hour Precip"
        }
    }

    // True for products that come from NEXRAD Level 3 files (not Level 2).
    var isLevel3: Bool {
        switch self {
        case .echoTops, .vil, .stormTotalPrecip, .oneHourPrecip: return true
        default: return false
        }
    }

    // Maps a Level 3 radar product to the corresponding Level3ProductCode.
    var level3ProductCode: Level3ProductCode? {
        switch self {
        case .echoTops:        return .echoTops
        case .vil:             return .digitalVIL
        case .stormTotalPrecip: return .stormTotalPrecip
        case .oneHourPrecip:   return .oneHourPrecip
        default:               return nil
        }
    }
}

// MARK: - Probe result

struct ProbeResult: Sendable {
    let coordinate: CLLocationCoordinate2D
    let bearing: Double
    let rangeKm: Double
    let description: String
}

enum AnimationSpeed: Double, CaseIterable, Identifiable {
    case slow   = 1.2
    case normal = 0.6
    case fast   = 0.25

    var id: Double { rawValue }
    var interval: Double { rawValue }

    var displayName: String {
        switch self {
        case .slow:   "Slow"
        case .normal: "Normal"
        case .fast:   "Fast"
        }
    }
}
