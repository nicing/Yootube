import Foundation

struct WatchEntry: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let watchedAt: Date

    var url: URL {
        URL(string: "http://127.0.0.1:38473/watch?v=\(id)")!
    }
    var thumbnailURL: URL {
        URL(string: "http://127.0.0.1:38473/vi/\(id)/mqdefault.jpg")!
    }
}

@MainActor
final class WatchHistory: ObservableObject {
    @Published private(set) var entries: [WatchEntry]
    private let defaults: UserDefaults
    private let key = "recentlyWatchedVideos"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([WatchEntry].self, from: $0) } ?? []
    }

    func reload() {
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([WatchEntry].self, from: $0) } ?? []
    }

    func record(id: String, title: String) {
        entries.removeAll { $0.id == id }
        entries.insert(WatchEntry(id: id, title: title, watchedAt: Date()), at: 0)
        entries = Array(entries.prefix(30))
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }

    @discardableResult
    func replaceAll(with imported: [WatchEntry]) -> Bool {
        guard Self.isValid(imported), let data = try? JSONEncoder().encode(imported) else { return false }
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else { return false }
        entries = imported
        return true
    }

    nonisolated static func isValid(_ entries: [WatchEntry]) -> Bool {
        entries.count <= 30 && Set(entries.map(\.id)).count == entries.count && entries.allSatisfy {
            VideoRoute.watchURL(id: $0.id) != nil && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
