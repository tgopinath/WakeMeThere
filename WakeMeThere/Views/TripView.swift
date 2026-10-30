import SwiftUI
import MapKit

/// Live view while travelling: map with the alarm zone and remaining distance.
struct TripView: View {
    @EnvironmentObject private var trip: TripManager
    @State private var camera: MapCameraPosition = .automatic
    @State private var confirmEnd = false

    var body: some View {
        if let destination = trip.activeTrip {
            ZStack(alignment: .bottom) {
                Map(position: $camera) {
                    UserAnnotation()
                    MapCircle(center: destination.coordinate, radius: destination.radius)
                        .foregroundStyle(Color.accentColor.opacity(0.18))
                        .stroke(Color.accentColor, lineWidth: 2)
                    Marker(destination.name, systemImage: "alarm.fill", coordinate: destination.coordinate)
                        .tint(Color.accentColor)
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .ignoresSafeArea()
                .onAppear { fitCamera(animated: false) }
                .onChange(of: trip.location == nil) { fitCamera(animated: true) }

                panel(for: destination)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .confirmationDialog("End this trip?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End trip", role: .destructive) { trip.endTrip() }
            } message: {
                Text("The arrival alarm for \(destination.name) will be turned off.")
            }
        }
    }

    /// Frame both you and the alarm zone, leaving room for the panel at the bottom.
    private func fitCamera(animated: Bool) {
        guard let destination = trip.activeTrip else { return }
        let pad = destination.radius / 111_000
        var lats = [destination.latitude - pad, destination.latitude + pad]
        var lons = [destination.longitude - pad, destination.longitude + pad]
        if let here = trip.location?.coordinate {
            lats.append(here.latitude)
            lons.append(here.longitude)
        }
        let latSpan = (lats.max()! - lats.min()!) * 2.1
        let lonSpan = (lons.max()! - lons.min()!) * 1.4
        let center = CLLocationCoordinate2D(
            latitude: (lats.max()! + lats.min()!) / 2 - latSpan * 0.18,
            longitude: (lons.max()! + lons.min()!) / 2
        )
        let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) { camera = .region(region) }
        } else {
            camera = .region(region)
        }
    }

    private func panel(for destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HEADING TO")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text(destination.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                Label(trip.isSnoozed ? "Snoozed" : "Armed",
                      systemImage: trip.isSnoozed ? "zzz" : "alarm.waves.left.and.right.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(trip.distance.map(Format.distance) ?? "Locating…")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.snappy, value: trip.distance)
                    if trip.distance != nil {
                        Text("to go")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: trip.progress)
                    .tint(Color.accentColor)
                HStack {
                    Label("Rings within \(Format.distance(destination.radius))", systemImage: "bell.fill")
                    Spacer()
                    if let eta = trip.eta {
                        Label("Alarm in ~\(Format.duration(eta))", systemImage: "clock.fill")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Text("You can lock your phone now. Keep the volume up — the alarm plays even in silent mode.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    confirmEnd = true
                } label: {
                    Text("End trip").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                #if DEBUG
                Button {
                    trip.testAlarm()
                } label: {
                    Text("Test alarm").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                #endif
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
    }
}
