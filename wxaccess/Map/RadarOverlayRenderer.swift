import MapKit
import CoreGraphics

final class RadarOverlayRenderer: MKOverlayRenderer {
    private let radarOverlay: RadarOverlay

    init(overlay: RadarOverlay) {
        self.radarOverlay = overlay
        super.init(overlay: overlay)
        self.alpha = 0.75
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        let drawRect = rect(for: radarOverlay.boundingMapRect)
        ctx.saveGState()
        ctx.translateBy(x: drawRect.midX, y: drawRect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -drawRect.midX, y: -drawRect.midY)
        ctx.draw(radarOverlay.image, in: drawRect)
        ctx.restoreGState()
    }

    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        radarOverlay.boundingMapRect.intersects(mapRect)
    }
}
