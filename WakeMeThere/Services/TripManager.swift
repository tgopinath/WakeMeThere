import Foundation
import CoreLocation
import UserNotifications

/// Tracks the user's position during a trip and rings the alarm on approach.
///
/// Two layers keep the alarm reliable:
/// 1. Continuous background location updates (with a background activity session)
///    compute the live distance and fire when inside the radius.
/// 2. A geofence (region monitoring) acts as a backup — with "Always" permission,
///    iOS relaunches the app on entry even if it was terminated.
@MainActor
final class TripManager: NSObject, ObservableObject {
    static let shared = TripManager()

    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var location: CLLocation?
    @Published private(set) var activeTrip: Destination?
    @Published private(set) var distance: CLLocationDistance?
    @Published private(set) var startDistance: CLLocationDistance?
    @Published private(set) var isRinging = false
    @Published private(set) var isSnoozed = false
    @Published private(set) var startedAt: Date?

    private let manager = CLLocationManager()
    private let alarm = AlarmPlayer()
    private var backgroundSession: CLBackgroundActivitySession?
    private var hasFired = false
    private var snoozeTask: Task<Void, Never>?
    private let activeTripKey = "activeTrip"
    private let startedAtKey = "activeTripStartedAt"
    static let snoozeSeconds: TimeInterval = 60

    private override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters

        // Resume a trip that was running when the app was terminated / relaunched by a geofence.
        if let data = UserDefaults.standard.data(forKey: activeTripKey),
           let trip = try? JSONDecoder().decode(Destination.self, from: data) {
            start(trip, startedAt: UserDefaults.standard.object(forKey: startedAtKey) as? Date)
        } else if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// Remaining distance until the alarm boundary.
    var remainingToAlarm: CLLocationDistance? {
        guard let distance, let trip = activeTrip else { return nil }
        return max(0, distance - trip.radius)
    }

    var progress: Double {
        guard let remainingToAlarm, let startDistance, let trip = activeTrip else { return 0 }
        let total = max(1, startDistance - trip.radius)
        return min(1, max(0, 1 - remainingToAlarm / total))
    }

    var eta: TimeInterval? {
        guard let remainingToAlarm, let speed = location?.speed, speed > 1.5 else { return nil }
        return remainingToAlarm / speed
    }

    // MARK: - Permissions

    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Ask for "Always" in context, right when the user starts their first trip.
    private func requestAlwaysIfNeeded() {
        if authorization == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        } else if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Trip lifecycle

    func start(_ destination: Destination, startedAt: Date? = nil) {
        activeTrip = destination
        hasFired = false
        isSnoozed = false
        distance = nil
        startDistance = nil
        self.startedAt = startedAt ?? Date()
        if let data = try? JSONEncoder().encode(destination) {
            UserDefaults.standard.set(data, forKey: activeTripKey)
            UserDefaults.standard.set(self.startedAt, forKey: startedAtKey)
        }

        requestAlwaysIfNeeded()

        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        backgroundSession = CLBackgroundActivitySession()
        manager.startUpdatingLocation()

        if CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
            let region = CLCircularRegion(
                center: destination.coordinate,
                radius: min(destination.radius, manager.maximumRegionMonitoringDistance),
                identifier: destination.id.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }

        if let location { handle(location) }
    }

    func endTrip() {
        if let trip = activeTrip {
            DestinationStore.shared.log(TripRecord(
                destinationName: trip.name,
                startedAt: startedAt ?? Date(),
                endedAt: Date(),
                outcome: hasFired ? .arrived : .ended
            ))
        }
        snoozeTask?.cancel()
        snoozeTask = nil
        alarm.stop()
        isRinging = false
        isSnoozed = false
        activeTrip = nil
        startedAt = nil
        distance = nil
        startDistance = nil
        UserDefaults.standard.removeObject(forKey: activeTripKey)
        UserDefaults.standard.removeObject(forKey: startedAtKey)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Debug helper: ring the alarm now to preview the experience.
    func testAlarm() {
        guard activeTrip != nil else { return }
        fire()
    }

    /// Silence the alarm and ring again after a minute — for the "five more minutes" moment.
    func snooze() {
        guard isRinging, let tripID = activeTrip?.id else { return }
        alarm.stop()
        isRinging = false
        isSnoozed = true
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        snoozeTask?.cancel()
        snoozeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.snoozeSeconds * 1_000_000_000))
            guard let self, !Task.isCancelled, self.activeTrip?.id == tripID else { return }
            self.isSnoozed = false
            self.hasFired = false
            self.fire()
        }
    }

    // MARK: - Location handling

    private func handle(_ newLocation: CLLocation) {
        location = newLocation
        guard let trip = activeTrip else { return }

        let d = newLocation.distance(from: trip.location)
        distance = d
        if startDistance == nil || d > (startDistance ?? 0) { startDistance = d }

        tuneAccuracy(remaining: d - trip.radius)

        // Ignore stale or very imprecise fixes to avoid false alarms.
        let isFresh = abs(newLocation.timestamp.timeIntervalSinceNow) < 60
        let isPrecise = newLocation.horizontalAccuracy >= 0
            && newLocation.horizontalAccuracy <= max(150, trip.radius)
        if d <= trip.radius && isFresh && isPrecise && !isSnoozed {
            fire()
        }
    }

    /// Save battery while far away, sharpen precision as the stop approaches.
    private func tuneAccuracy(remaining: CLLocationDistance) {
        let (accuracy, filter): (CLLocationAccuracy, CLLocationDistance) =
            remaining > 20_000 ? (kCLLocationAccuracyHundredMeters, 300) :
            remaining > 5_000  ? (kCLLocationAccuracyNearestTenMeters, 80) :
                                 (kCLLocationAccuracyBest, 15)
        if manager.desiredAccuracy != accuracy { manager.desiredAccuracy = accuracy }
        if manager.distanceFilter != filter { manager.distanceFilter = filter }
    }

    private func fire() {
        guard !hasFired, !isSnoozed, let trip = activeTrip else { return }
        hasFired = true
        isRinging = true
        alarm.start()

        let content = UNMutableNotificationContent()
        content.title = "Wake up — you're almost there!"
        content.body = distance.map { "\(trip.name) is \(Format.distance($0)) away. Time to get ready." }
            ?? "You're approaching \(trip.name). Time to get ready."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(AlarmTone.notificationSoundName))
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: "arrival-\(trip.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension TripManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.handle(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in
            if id == self.activeTrip?.id.uuidString, !self.isSnoozed { self.fire() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
