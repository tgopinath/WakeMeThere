import Foundation

/// A finished trip, shown in "Recent trips".
struct TripRecord: Identifiable, Codable, Hashable {
    enum Outcome: String, Codable {
        case arrived   // the alarm rang
        case ended     // the user ended the trip before arriving
    }

    var id = UUID()
    var destinationName: String
    var startedAt: Date
    var endedAt: Date
    var outcome: Outcome
}

/// A stop the user just deleted, kept briefly so it can be restored.
struct DeletedStop: Equatable {
    let destination: Destination
    let index: Int
}

/// Saved stops and trip history, persisted to UserDefaults.
@MainActor
final class DestinationStore: ObservableObject {
    static let shared = DestinationStore()

    @Published private(set) var destinations: [Destination] = []
    @Published private(set) var history: [TripRecord] = []
    @Published private(set) var lastDeleted: DeletedStop?

    private let stopsKey = "savedDestinations"
    private let historyKey = "tripHistory"

    private init() {
        destinations = load([Destination].self, key: stopsKey) ?? []
        history = load([TripRecord].self, key: historyKey) ?? []
    }

    // MARK: Stops

    func add(_ destination: Destination) {
        destinations.insert(destination, at: 0)
        saveStops()
    }

    func update(_ destination: Destination) {
        guard let index = destinations.firstIndex(where: { $0.id == destination.id }) else { return }
        destinations[index] = destination
        saveStops()
    }

    func delete(_ destination: Destination) {
        guard let index = destinations.firstIndex(where: { $0.id == destination.id }) else { return }
        destinations.remove(at: index)
        lastDeleted = DeletedStop(destination: destination, index: index)
        saveStops()
    }

    func delete(at offsets: IndexSet) {
        // Only the last one can be undone when several are removed at once.
        if let first = offsets.first, offsets.count == 1 {
            lastDeleted = DeletedStop(destination: destinations[first], index: first)
        } else {
            lastDeleted = nil
        }
        destinations.remove(atOffsets: offsets)
        saveStops()
    }

    func undoDelete() {
        guard let deleted = lastDeleted else { return }
        destinations.insert(deleted.destination, at: min(deleted.index, destinations.count))
        lastDeleted = nil
        saveStops()
    }

    func clearUndo() { lastDeleted = nil }

    // MARK: History

    func log(_ record: TripRecord) {
        history.insert(record, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        saveHistory()
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // MARK: Demo data (screenshots and previews)

    func replaceAll(stops: [Destination], history: [TripRecord]) {
        destinations = stops
        self.history = history
        saveStops()
        saveHistory()
    }

    // MARK: Persistence

    private func saveStops() { save(destinations, key: stopsKey) }
    private func saveHistory() { save(history, key: historyKey) }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
