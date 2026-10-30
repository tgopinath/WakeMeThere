import Foundation
import MapKit

/// Autocomplete for stops, stations and addresses.
@MainActor
final class PlaceSearch: NSObject, ObservableObject {
    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func bias(to location: CLLocation?) {
        guard let location else { return }
        completer.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 200_000,
            longitudinalMeters: 200_000
        )
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        if #available(iOS 26.0, *) {
            return item.location.coordinate
        } else {
            return item.placemark.coordinate
        }
    }
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.results = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
