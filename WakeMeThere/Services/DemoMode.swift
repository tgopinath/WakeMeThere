#if DEBUG
import Foundation

/// Debug-only launch arguments that put the app into a known state, used for
/// portfolio screenshots and design reviews:
///   -demo          sample stops and trip history
///   -demo trip     …and a trip in progress
///   -demo ring     …and the alarm ringing
///   -demo undo     …and a stop just deleted, showing the undo toast
///   -demo trips    …opened on the Trips tab
enum DemoMode {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var scene: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func applyIfRequested() {
        guard isActive else { return }
        let now = Date()
        let stops = [
            Destination(name: "Guindy Metro", subtitle: "Anna Salai, Guindy", latitude: 13.0090, longitude: 80.2130, radius: 1000),
            Destination(name: "Chennai Central", subtitle: "Park Town", latitude: 13.0827, longitude: 80.2757, radius: 2000),
            Destination(name: "Zoho Estancia", subtitle: "Potheri", latitude: 12.8259, longitude: 80.0453, radius: 800),
            Destination(name: "Egmore Station", subtitle: "Egmore", latitude: 13.0780, longitude: 80.2614, radius: 1500),
        ]
        let history = [
            TripRecord(destinationName: "Zoho Estancia", startedAt: now.addingTimeInterval(-26 * 3600), endedAt: now.addingTimeInterval(-25.2 * 3600), outcome: .arrived),
            TripRecord(destinationName: "Chennai Central", startedAt: now.addingTimeInterval(-3 * 86400), endedAt: now.addingTimeInterval(-3 * 86400 + 2900), outcome: .arrived),
            TripRecord(destinationName: "Guindy Metro", startedAt: now.addingTimeInterval(-5 * 86400), endedAt: now.addingTimeInterval(-5 * 86400 + 900), outcome: .ended),
        ]
        UserDefaults.standard.removeObject(forKey: "activeTrip")
        DestinationStore.shared.replaceAll(stops: stops, history: history)

        let trip = TripManager.shared
        if trip.activeTrip != nil { trip.endTrip() }
        DestinationStore.shared.replaceAll(stops: stops, history: history)
        switch scene {
        case "trip":
            trip.start(stops[0], startedAt: now.addingTimeInterval(-14 * 60))
        case "ring":
            trip.start(stops[0], startedAt: now.addingTimeInterval(-22 * 60))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                trip.testAlarm()
            }
        case "undo":
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                DestinationStore.shared.delete(stops[3])
            }
        default:
            break
        }
    }
}
#endif
