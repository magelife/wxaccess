import SwiftUI
import MapKit
import CoreLocation

// NSViewRepresentable wrapper around MKMapView for full overlay control.
struct MainMapView: NSViewRepresentable {
    @Environment(AppState.self) var appState

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = false

        // Center on selected site initially
        let region = MKCoordinateRegion(
            center: appState.selectedSite.coordinate,
            latitudinalMeters: 800_000,
            longitudinalMeters: 800_000
        )
        map.setRegion(region, animated: false)

        // Accessibility: expose the map with a descriptive label (macOS NSAccessibility API)
        map.setAccessibilityLabel("Weather radar map")
        map.setAccessibilityHelp("Scroll or pinch to zoom. Use the data panel below for VoiceOver navigation.")
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        // Remove existing radar overlays
        let oldRadar = map.overlays.filter { $0 is RadarOverlay }
        map.removeOverlays(oldRadar)

        // Add new radar overlay if sweep is available
        if let sweep = appState.currentSweep {
            let overlay = RadarOverlay(sweep: sweep)
            map.addOverlay(overlay, level: .aboveRoads)
        }

        // Remove old alert polygon overlays
        let oldAlerts = map.overlays.filter { $0 is AlertPolygon }
        map.removeOverlays(oldAlerts)

        // Add alert polygons
        for alert in appState.alerts where !alert.polygon.isEmpty {
            map.addOverlay(AlertPolygon(alert: alert), level: .aboveLabels)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let radar = overlay as? RadarOverlay {
                return RadarOverlayRenderer(overlay: radar)
            }
            if let alertPoly = overlay as? AlertPolygon {
                let renderer = MKPolygonRenderer(polygon: alertPoly.polygon)
                renderer.strokeColor = alertPoly.strokeColor
                renderer.fillColor   = alertPoly.fillColor
                renderer.lineWidth   = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Alert polygon overlay

final class AlertPolygon: NSObject, MKOverlay, @unchecked Sendable {
    let alert: NWSAlert
    let polygon: MKPolygon

    var coordinate: CLLocationCoordinate2D { polygon.coordinate }
    var boundingMapRect: MKMapRect { polygon.boundingMapRect }

    var strokeColor: NSColor {
        switch alert.severity {
        case .extreme:  .red
        case .severe:   .orange
        case .moderate: .yellow
        default:        .white
        }
    }

    var fillColor: NSColor { strokeColor.withAlphaComponent(0.15) }

    init(alert: NWSAlert) {
        self.alert = alert
        self.polygon = MKPolygon(coordinates: alert.polygon, count: alert.polygon.count)
        super.init()
    }
}
