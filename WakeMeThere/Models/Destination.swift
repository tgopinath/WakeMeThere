import Foundation
import CoreLocation

/// A place the user wants to be woken up before reaching.
struct Destination: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    /// Distance from the destination (in meters) at which the alarm rings.
    var radius: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

enum Format {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int((meters / 10).rounded()) * 10) m"
        }
        return meters < 10_000
            ? String(format: "%.1f km", meters / 1000)
            : "\(Int((meters / 1000).rounded())) km"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
