import CoreLocation
import Foundation

struct NEXRADSite: Sendable, Identifiable, Hashable {
    let icao: String
    let name: String
    let state: String
    let latitude: Double
    let longitude: Double
    let elevationMeters: Int

    var id: String { icao }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var displayName: String { "\(icao) – \(name), \(state)" }
}
