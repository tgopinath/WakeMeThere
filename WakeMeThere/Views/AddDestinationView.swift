import SwiftUI
import MapKit

struct AddDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var trip: TripManager
    @StateObject private var search = PlaceSearch()

    let existing: Destination?
    let onSave: (Destination, _ startNow: Bool) -> Void
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var subtitle: String
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var radius: Double
    @State private var camera: MapCameraPosition
    @State private var isSearching = false
    @State private var confirmDelete = false

    init(
        existing: Destination? = nil,
        onSave: @escaping (Destination, _ startNow: Bool) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: existing?.name ?? "")
        _subtitle = State(initialValue: existing?.subtitle ?? "")
        _coordinate = State(initialValue: existing?.coordinate)
        _radius = State(initialValue: existing?.radius ?? 1000)
        if let existing {
            let span = max(existing.radius * 3, 2000)
            _camera = State(initialValue: .region(MKCoordinateRegion(
                center: existing.coordinate, latitudinalMeters: span, longitudinalMeters: span)))
        } else {
            _camera = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    private let presets: [Double] = [300, 500, 1000, 2000, 5000]

    var body: some View {
        NavigationStack {
            Group {
                if isSearching && !search.query.isEmpty {
                    resultsList
                } else {
                    editor
                }
            }
            .navigationTitle(existing == nil ? "New stop" : "Edit stop")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $search.query,
                isPresented: $isSearching,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search a station, stop or address"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(startNow: false) }
                        .disabled(!canSave)
                }
            }
            .onAppear { search.bias(to: trip.location) }
            .confirmationDialog("Delete this stop?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete stop", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("You can undo this for a few seconds from the home screen.")
            }
        }
    }

    // MARK: - Search results

    private var resultsList: some View {
        List(search.results, id: \.self) { result in
            Button {
                select(result)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title).foregroundStyle(.primary)
                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Map + settings

    private var editor: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    if let coordinate {
                        MapCircle(center: coordinate, radius: radius)
                            .foregroundStyle(Color.accentColor.opacity(0.18))
                            .stroke(Color.accentColor, lineWidth: 2)
                        Marker(name.isEmpty ? "Stop" : name, systemImage: "alarm.fill", coordinate: coordinate)
                            .tint(Color.accentColor)
                    }
                }
                .onTapGesture { point in
                    if let tapped = proxy.convert(point, from: .local) {
                        dropPin(at: tapped)
                    }
                }
            }
            .overlay(alignment: .top) {
                if coordinate == nil {
                    Label("Search above, or tap the map to drop a pin", systemImage: "hand.tap.fill")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 12)
                }
            }

            settingsPanel
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Name (e.g. Home, Office, Central Station)", text: $name)
                .font(.headline)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Wake me up within")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.distance(radius))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                Slider(value: $radius, in: 200...10_000, step: 100)
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button(Format.distance(preset)) {
                            withAnimation(.snappy) { radius = preset }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            radius == preset ? Color.accentColor : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(radius == preset ? Color.white : Color.primary)
                    }
                }
                Text("Tip: on fast trains or highways, pick 2–5 km so you have time to get ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                save(startNow: true)
            } label: {
                Label("Save & start trip", systemImage: "alarm.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!canSave)

            if existing != nil, onDelete != nil {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete stop", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private var canSave: Bool { coordinate != nil }

    private func select(_ result: MKLocalSearchCompletion) {
        Task {
            guard let found = await search.resolve(result) else { return }
            name = result.title
            subtitle = result.subtitle
            isSearching = false
            search.query = ""
            setCoordinate(found)
        }
    }

    private func dropPin(at point: CLLocationCoordinate2D) {
        setCoordinate(point)
        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: point.latitude, longitude: point.longitude)
        ) { placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            if name.isEmpty { name = placemark.name ?? placemark.locality ?? "Dropped pin" }
            subtitle = [placemark.locality, placemark.administrativeArea]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
    }

    private func setCoordinate(_ new: CLLocationCoordinate2D) {
        coordinate = new
        withAnimation(.snappy) {
            camera = .region(MKCoordinateRegion(
                center: new,
                latitudinalMeters: max(radius * 3, 2000),
                longitudinalMeters: max(radius * 3, 2000)
            ))
        }
    }

    private func save(startNow: Bool) {
        guard let coordinate else { return }
        let destination = Destination(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "My stop" : name,
            subtitle: subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: radius
        )
        onSave(destination, startNow)
        dismiss()
    }
}
