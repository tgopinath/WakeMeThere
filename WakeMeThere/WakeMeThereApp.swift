import SwiftUI
import UserNotifications

@main
struct WakeMeThereApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = DestinationStore.shared
    @ObservedObject private var trip = TripManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(trip)
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AlarmTone.installNotificationSound()
        #if DEBUG
        DemoMode.applyIfRequested()
        #endif
        // Create the location manager at launch so geofence events delivered on a
        // background relaunch reach its delegate.
        _ = TripManager.shared
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

struct RootView: View {
    @EnvironmentObject private var trip: TripManager

    var body: some View {
        Group {
            if trip.activeTrip != nil {
                TripView()
            } else {
                HomeView()
            }
        }
        .animation(.snappy, value: trip.activeTrip)
        .fullScreenCover(isPresented: Binding(
            get: { trip.isRinging },
            // Dismissal is driven by TripManager ("I'm awake" or Snooze), never by the cover itself.
            set: { _ in }
        )) {
            RingingView()
        }
        .task {
            #if DEBUG
            if DemoMode.isActive { return }
            #endif
            trip.requestPermissions()
        }
    }
}
