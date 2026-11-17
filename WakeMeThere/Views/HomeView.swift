import SwiftUI
import MapKit

/// Home: a tab bar with your saved stops and your recent trips.
struct HomeView: View {
    enum Tab: Hashable { case stops, trips }

    @EnvironmentObject private var store: DestinationStore
    @State private var tab: Tab = HomeView.initialTab

    var body: some View {
        TabView(selection: $tab) {
            StopsTab()
                .tabItem { Label("Stops", systemImage: "mappin.and.ellipse") }
                .tag(Tab.stops)
            TripsTab()
                .tabItem { Label("Trips", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.trips)
        }
    }

    private static var initialTab: Tab {
        #if DEBUG
        if DemoMode.scene == "trips" { return .trips }
        #endif
        return .stops
    }
}

// MARK: - Stops tab

private struct StopsTab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var trip: TripManager
    @EnvironmentObject private var store: DestinationStore
    @State private var showingAdd = StopsTab.demoScene == "add"
    @State private var editing: Destination?
    @State private var pendingDelete: Destination?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Map(position: $camera) {
                        UserAnnotation()
                        ForEach(store.destinations) { destination in
                            Marker(destination.name, systemImage: "alarm.fill", coordinate: destination.coordinate)
                                .tint(Color.accentColor)
                            MapCircle(center: destination.coordinate, radius: destination.radius)
                                .foregroundStyle(Color.accentColor.opacity(0.12))
                        }
                    }
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("Map of your stops")
                }

                if !trip.isAuthorized {
                    Section { PermissionCard() }
                }

                stopsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Wake Me There")
            .toolbar {
                if !store.destinations.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add stop", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let deleted = store.lastDeleted {
                    UndoToast(name: deleted.destination.name) {
                        withAnimation(.snappy) { store.undoDelete() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: deleted.destination.id) {
                        AccessibilityNotification.Announcement("Deleted \(deleted.destination.name). Undo available.").post()
                        // VoiceOver users get longer to reach the Undo button.
                        let seconds: UInt64 = UIAccessibility.isVoiceOverRunning ? 10 : 5
                        try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                        withAnimation(.snappy) { store.clearUndo() }
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: store.lastDeleted)
            .task {
                if StopsTab.demoScene == "edit" {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    editing = store.destinations.first
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddDestinationView { destination, startNow in
                    store.add(destination)
                    if startNow { trip.start(destination) }
                }
            }
            .sheet(item: $editing) { destination in
                AddDestinationView(existing: destination) { updated, startNow in
                    store.update(updated)
                    if startNow { trip.start(updated) }
                } onDelete: {
                    withAnimation(.snappy) { store.delete(destination) }
                }
            }
            .confirmationDialog(
                "Delete \"\(pendingDelete?.name ?? "stop")\"?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete stop", role: .destructive) {
                    if let pendingDelete { withAnimation(.snappy) { store.delete(pendingDelete) } }
                }
            } message: {
                Text("You can undo this for a few seconds.")
            }
        }
    }

    private static var demoScene: String? {
        #if DEBUG
        return DemoMode.scene
        #else
        return nil
        #endif
    }

    // MARK: Sections

    private var stopsSection: some View {
        Section {
            if store.destinations.isEmpty {
                EmptyStateRow { showingAdd = true }
            } else {
                ForEach(store.destinations) { destination in
                    DestinationRow(destination: destination) {
                        trip.start(destination)
                    }
                    .contentShape(Rectangle())
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.snappy) { store.delete(destination) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editing = destination
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.gray)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            trip.start(destination)
                        } label: {
                            Label("Start", systemImage: "alarm.fill")
                        }
                        .tint(Color.accentColor)
                    }
                    .contextMenu {
                        Button { trip.start(destination) } label: { Label("Start trip", systemImage: "alarm") }
                        Button { editing = destination } label: { Label("Edit stop", systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) { pendingDelete = destination } label: {
                            Label("Delete stop", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    withAnimation(.snappy) { store.delete(at: offsets) }
                }
            }
        } header: {
            Text("Your stops")
        } footer: {
            if !store.destinations.isEmpty {
                Text("Swipe left to edit or delete, right to start. The alarm rings as you get close, even on silent.")
            }
        }
    }

}

// MARK: - Trips tab

private struct TripsTab: View {
    @EnvironmentObject private var store: DestinationStore
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty {
                    ContentUnavailableView(
                        "No trips yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished trips show up here, with whether the alarm woke you up.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(store.history) { record in
                                HistoryRow(record: record)
                            }
                            .onDelete { offsets in
                                withAnimation(.snappy) { store.deleteHistory(at: offsets) }
                            }
                        } header: {
                            Text(summary)
                        } footer: {
                            Text("Swipe left on a trip to delete it.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recent trips")
            .toolbar {
                if !store.history.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Clear all recent trips?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    withAnimation(.snappy) { store.clearHistory() }
                }
            } message: {
                Text("This removes your trip history from this iPhone.")
            }
        }
    }

    private var summary: String {
        let woke = store.history.filter { $0.outcome == .arrived }.count
        let trips = store.history.count == 1 ? "1 trip" : "\(store.history.count) trips"
        return "\(trips) · woke you up \(woke == 1 ? "once" : "\(woke) times")"
    }
}

// MARK: - Rows

private struct DestinationRow: View {
    @EnvironmentObject private var trip: TripManager
    @Environment(\.editMode) private var editMode
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40
    let destination: Destination
    let onStart: () -> Void

    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        // At accessibility sizes the Start button moves under the text so names aren't cut off.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            HStack(spacing: 14) {
                if !typeSize.isAccessibilitySize {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .font(.headline)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 2) { metadata }
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { metadata }
                                VStack(alignment: .leading, spacing: 2) { metadata }
                            }
                        }
                    }
                    .font(.subheadline)
                    .labelStyle(CompactLabelStyle())
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }

            if !isEditing {
                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Start trip to \(destination.name)")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var metadata: some View {
        Label("Rings within \(Format.distance(destination.radius))", systemImage: "bell.fill")
        if let here = trip.location {
            Label("\(Format.distance(here.distance(from: destination.location))) away", systemImage: "location.fill")
        }
    }
}

/// Icon + text with a tight gap, for dense metadata rows.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.caption2)
            configuration.title
        }
    }
}

private struct HistoryRow: View {
    let record: TripRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.outcome == .arrived ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(record.outcome == .arrived ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.destinationName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.endedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let outcome = record.outcome == .arrived ? "Woke you up" : "Ended early"
        return "\(outcome) · \(Format.duration(record.endedAt.timeIntervalSince(record.startedAt)))"
    }
}

private struct UndoToast: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let name: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.fill")
                .foregroundStyle(.secondary)
            Text("Deleted \"\(name)\"")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Undo delete")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

private struct EmptyStateRow: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Nap on the way", systemImage: "bed.double.fill")
        } description: {
            Text("Add your stop and we'll wake you up before you get there.")
        } actions: {
            Button("Add a stop", systemImage: "plus", action: onAdd)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PermissionCard: View {
    @EnvironmentObject private var trip: TripManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Location access needed")
                    .font(.headline)
                Text("Wake Me There needs your location to know when you're close to your stop.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(trip.authorization == .notDetermined ? "Allow location" : "Open Settings") {
                    if trip.authorization == .notDetermined {
                        trip.requestPermissions()
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.vertical, 4)
    }
}
