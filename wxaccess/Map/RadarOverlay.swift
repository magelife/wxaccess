import MapKit
import CoreLocation
import CoreGraphics

// MKOverlay that holds a rasterized radar sweep image and its bounding region.
final class RadarOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let coordinate: CLLocationCoordinate2D  // radar site
    let boundingMapRect: MKMapRect
    let image: CGImage
    let sweep: RadarSweep

    init(sweep: RadarSweep, imageSize: Int = 1024) {
        self.sweep = sweep
        self.coordinate = sweep.site.coordinate

        let maxRangeKm = max(sweep.maxRangeKm, 1)
        // Build a square bounding box centred on the radar site.
        let originPoint = MKMapPoint(sweep.site.coordinate)
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(sweep.site.coordinate.latitude)
        let halfSideMapPoints = (maxRangeKm * 1000) / metersPerMapPoint
        self.boundingMapRect = MKMapRect(
            x: originPoint.x - halfSideMapPoints,
            y: originPoint.y - halfSideMapPoints,
            width:  halfSideMapPoints * 2,
            height: halfSideMapPoints * 2
        )

        self.image = RadarOverlay.rasterize(sweep: sweep, size: imageSize, maxRangeKm: maxRangeKm)
        super.init()
    }

    // MARK: - Rasterization

    // Convert polar radial data to a square CGImage via inverse-mapping.
    // Each pixel's (azimuth, range) is computed and the nearest gate value looked up.
    private static func rasterize(sweep: RadarSweep, size: Int, maxRangeKm: Double) -> CGImage {
        let width  = size
        let height = size
        var pixels = [UInt32](repeating: 0, count: width * height)

        // Build a lookup: azimuth (rounded to nearest 0.5°) → Radial
        var radialMap: [Int: Radial] = [:]
        for radial in sweep.radials {
            let key = Int((radial.azimuth * 2).rounded())  // half-degree resolution
            radialMap[key] = radial
        }

        let half = Double(size) / 2.0

        for row in 0..<height {
            for col in 0..<width {
                let dx = (Double(col) - half) / half  // -1…+1, east positive
                let dy = (half - Double(row)) / half  // -1…+1, north positive
                let distNorm = sqrt(dx * dx + dy * dy)
                guard distNorm <= 1.0 else { continue }

                let rangeKm = distNorm * maxRangeKm
                // Azimuth: clockwise from north
                var az = atan2(dx, dy) * 180.0 / .pi
                if az < 0 { az += 360.0 }

                let azKey = Int((az * 2).rounded()) % 720
                guard let radial = radialMap[azKey] ?? radialMap[(azKey + 1) % 720] ?? radialMap[(azKey - 1 + 720) % 720],
                      radial.gateSizeMeters > 0 else { continue }

                let gateIndex = Int((rangeKm * 1000 - Double(radial.firstGateMeters)) / Double(radial.gateSizeMeters))
                guard let dbz = radial.physicalValue(gateIndex: gateIndex) else { continue }

                pixels[row * width + col] = reflectivityColor(dbz: dbz)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
              let image = ctx.makeImage()
        else {
            return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo,
                           provider: CGDataProvider(data: Data([0,0,0,0]) as CFData)!,
                           decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
        return image
    }

    // Standard NWS reflectivity color table (dBZ → RGBA uint32, RGBA order)
    private static func reflectivityColor(dbz: Float) -> UInt32 {
        switch dbz {
        case ..<5:   return 0
        case 5..<10: return rgba(0x00, 0xEC, 0xEC)
        case 10..<15: return rgba(0x01, 0x9F, 0xF4)
        case 15..<20: return rgba(0x03, 0x00, 0xF4)
        case 20..<25: return rgba(0x02, 0xFD, 0x02)
        case 25..<30: return rgba(0x01, 0xC5, 0x01)
        case 30..<35: return rgba(0x00, 0x8E, 0x00)
        case 35..<40: return rgba(0xFD, 0xF8, 0x02)
        case 40..<45: return rgba(0xE5, 0xBC, 0x00)
        case 45..<50: return rgba(0xFD, 0x95, 0x00)
        case 50..<55: return rgba(0xFD, 0x00, 0x00)
        case 55..<60: return rgba(0xD4, 0x00, 0x00)
        case 60..<65: return rgba(0xBC, 0x00, 0x00)
        case 65..<70: return rgba(0xF8, 0x00, 0xFD)
        case 70..<75: return rgba(0x98, 0x54, 0xC6)
        default:      return rgba(0xFF, 0xFF, 0xFF)
        }
    }

    private static func rgba(_ r: UInt32, _ g: UInt32, _ b: UInt32, a: UInt32 = 210) -> UInt32 {
        (r << 24) | (g << 16) | (b << 8) | a
    }
}
