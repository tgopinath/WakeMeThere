import SwiftUI

/// Full-screen alarm shown when the user reaches the wake-up zone.
struct RingingView: View {
    @EnvironmentObject private var trip: TripManager
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.25), Color(red: 0.93, green: 0.22, blue: 0.47)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ForEach(0..<3) { ring in
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 2)
                    .frame(width: 180, height: 180)
                    .scaleEffect(pulse ? 2.6 : 0.8)
                    .opacity(pulse ? 0 : 0.9)
                    .animation(
                        .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(ring) * 0.8),
                        value: pulse
                    )
            }
            .offset(y: -80)

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "alarm.waves.left.and.right.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .symbolEffect(.variableColor.iterative.reversing)
                    .padding(.bottom, 24)

                Text("Wake up!")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))

                if let destination = trip.activeTrip {
                    Text("You're approaching **\(destination.name)**")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                    if let distance = trip.distance {
                        Text("\(Format.distance(distance)) away")
                            .font(.headline)
                            .opacity(0.85)
                    }
                }

                Spacer()
                Spacer()

                VStack(spacing: 12) {
                    Button {
                        trip.endTrip()
                    } label: {
                        Text("I'm awake")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(red: 0.93, green: 0.22, blue: 0.47))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(.white, in: Capsule())
                    }

                    Button {
                        trip.snooze()
                    } label: {
                        Label("Snooze 1 min", systemImage: "zzz")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.white.opacity(0.18), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .foregroundStyle(.white)
            .padding()
        }
        .onAppear { pulse = true }
    }
}
