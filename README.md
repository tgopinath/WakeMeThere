# Wake Me There

A location-based travel alarm for iOS. Pick your stop, set how close you want to be woken, then nap. The alarm rings as you approach, even with the phone locked or on silent.

## Run it
1. Open `WakeMeThere.xcodeproj` in Xcode.
2. Install the iOS platform if you haven't yet: **Xcode → Settings → Components → iOS 26**.
3. Under **Signing & Capabilities**, choose your Team. Change the bundle ID if you need to.
4. Run it on an iPhone. Background location and alarms are best tested on a real device.
   - On the Simulator, use **Features → Location → Freeway Drive** or a custom GPX file to fake movement.
   - Debug builds have a **Test alarm** button on the trip screen.

## How it works
| Piece | File |
|---|---|
| Trip engine: live distance, adaptive GPS accuracy, geofence backup, resume after relaunch | `Services/TripManager.swift` |
| Looping alarm that plays on silent, plus vibration; the tone is generated, so there are no audio assets | `Services/AlarmPlayer.swift` |
| Place autocomplete (MapKit) | `Services/PlaceSearch.swift` |
| Home / New stop / Live trip / Ringing screens | `Views/` |

Reliability layers:
1. **Continuous background location**, held by a `CLBackgroundActivitySession`, checks the distance on every fix and fires inside the radius. Stale fixes and fixes less precise than the radius are ignored.
2. **Geofence (region monitoring)** as a backup. With "Always" permission, iOS relaunches the app on entry even if it was killed.
3. A **time-sensitive notification** with a custom ~25 s alarm sound, written to `Library/Sounds` at launch.

GPS accuracy drops when you're more than 20 km away and sharpens to best accuracy within 5 km, to save battery.

## Ideas for next steps
- AlarmKit (iOS 26) for system-level alarms that break through Focus
- A Live Activity or Dynamic Island showing distance remaining
- A snooze that re-arms at a smaller radius
- Recent trips and favourites, and choosing between several alarm tones
