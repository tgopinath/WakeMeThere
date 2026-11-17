import SwiftUI

/// Full-screen alarm shown when the user reaches the wake-up zone.
struct RingingView: View {
    @EnvironmentObject private var trip: TripManager
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    /// Warm alarm gradient, deep enough that white text passes WCAG AA (darker still with Increase Contrast).
    private var colors: [Color] {
        contrast == .increased
            ? [Color(red: 0.72, green: 0.22, blue: 0.08), Color(red: 0.66, green: 0.08, blue: 0.30)]
            : [Color(red: 0.88, green: 0.32, blue: 0.14), Color(red: 0.86, green: 0.16, blue: 0.40)]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if !reduceMotion {
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
            .accessibilityHidden(true)
            }

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "alarm.waves.left.and.right.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .symbolEffect(.variableColor.iterative.reversing, isActive: !reduceMotion)
                    .padding(.bottom, 24)
                    .accessibilityHidden(true)

                Text("Wake up!")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .accessibilityAddTraits(.isHeader)

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
                            .foregroundStyle(colors[1])
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
        .onAppear {
            pulse = true
            AccessibilityNotification.Announcement("Wake up! You're approaching your stop.").post()
        }
    }
}
