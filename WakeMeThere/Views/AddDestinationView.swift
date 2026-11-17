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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var mapHeight: CGFloat { typeSize.isAccessibilitySize ? 200 : 280 }

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
        Form {
            Section {
                map
                    .frame(height: mapHeight)
                    .listRowInsets(EdgeInsets())
            } footer: {
                if coordinate == nil {
                    Label("Search above, or tap the map to drop a pin.", systemImage: "hand.tap")
                }
            }

            Section("Name") {
                TextField("Name", text: $name, prompt: Text("Home, Office, Central Station"))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }

            Section {
                LabeledContent("Wake me up within") {
                    Text(Format.distance(radius))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                }
                Slider(value: $radius, in: 200...10_000, step: 100) {
                    Text("Alarm distance")
                } minimumValueLabel: {
                    Text("200 m").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("10 km").font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityValue(Format.distance(radius))
                Picker("Quick pick", selection: presetBinding) {
                    ForEach(presets, id: \.self) { preset in
                        Text(Format.distance(preset)).tag(Optional(preset))
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Alarm distance")
            } footer: {
                Text("On fast trains or highways, pick 2–5 km so you have time to get ready.")
            }

            Section {
                Button {
                    save(startNow: true)
                } label: {
                    Label("Save & start trip", systemImage: "alarm.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(!canSave)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if existing != nil, onDelete != nil {
                Section {
                    Button("Delete stop", role: .destructive) {
                        confirmDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var map: some View {
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
            .accessibilityLabel(coordinate == nil ? "Map. Search for a place to set your stop." : "Map showing your stop and alarm zone")
        }
    }

    /// The segmented quick-pick shows a selection only when the slider sits on a preset.
    private var presetBinding: Binding<Double?> {
        Binding(
            get: { presets.contains(radius) ? radius : nil },
            set: { if let value = $0 { withAnimation(reduceMotion ? nil : .snappy) { radius = value } } }
        )
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
        withAnimation(reduceMotion ? nil : .snappy) {
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
