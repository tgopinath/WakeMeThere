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
    @EnvironmentObject private var trip: TripManager
    @EnvironmentObject private var store: DestinationStore
    @State private var showingAdd = false
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: deleted.destination.id) {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        withAnimation(.snappy) { store.clearUndo() }
                    }
                }
            }
            .animation(.snappy, value: store.lastDeleted)
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
    let destination: Destination
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label(Format.distance(destination.radius), systemImage: "bell.fill")
                    if let here = trip.location {
                        Label("\(Format.distance(here.distance(from: destination.location))) away", systemImage: "location.fill")
                    }
                }
                .font(.subheadline)
                .labelStyle(CompactLabelStyle())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if editMode?.wrappedValue.isEditing != true {
                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
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
    }

    private var summary: String {
        let outcome = record.outcome == .arrived ? "Woke you up" : "Ended early"
        return "\(outcome) · \(Format.duration(record.endedAt.timeIntervalSince(record.startedAt)))"
    }
}

private struct UndoToast: View {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

private struct EmptyStateRow: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Nap on the way")
                .font(.headline)
            Text("Add your stop and we'll wake you up before you get there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add a stop", systemImage: "plus", action: onAdd)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct PermissionCard: View {
    @EnvironmentObject private var trip: TripManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(.orange)
                .font(.title3)
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
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }
}
