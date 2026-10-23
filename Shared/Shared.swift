import Foundation

/// One station, as the Drive Launcher radio API sends it (names only, never logos: see /radio on the website).
struct Station: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let frequency: String
    let language: String
    let url: String
    let format: String?

    /// "Sinhala · 105.3" style subtitle; empty parts are left out.
    var subtitle: String {
        [language, frequency].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// State shared by the menu bar app (which plays) and the widget (which only shows and sends commands),
/// kept in the app group's defaults.
enum Shared {
    static let group = "DH7LNR88KT.lk.semicolon.driveradio"
    static let commandNotification = "lk.semicolon.driveradio.command"
    static let api = URL(string: "https://drivelauncher.teachmeit.lk/api/v1/radio")!
    static let defaults = UserDefaults(suiteName: group) ?? .standard

    /// The last list from the server, else the list built into the app.
    static var stations: [Station] {
        if let data = defaults.data(forKey: "stations"),
           let list = try? JSONDecoder().decode([Station].self, from: data), !list.isEmpty {
            return list
        }
        return bundled
    }

    static var bundled: [Station] {
        guard let url = Bundle.main.url(forResource: "stations", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Station].self, from: data)) ?? []
    }

    static func save(stations: [Station]) {
        defaults.set(try? JSONEncoder().encode(stations), forKey: "stations")
        defaults.set(Date(), forKey: "stationsFetched")
    }

    static var stationsFetched: Date? { defaults.object(forKey: "stationsFetched") as? Date }

    static var currentId: Int? {
        get { defaults.object(forKey: "currentId") as? Int }
        set { defaults.set(newValue, forKey: "currentId") }
    }

    /// "stopped", "connecting", "playing" or "failed".
    static var state: String {
        get { defaults.string(forKey: "state") ?? "stopped" }
        set { defaults.set(newValue, forKey: "state") }
    }

    /// The song or show the station is sending right now, when it sends one.
    static var nowPlaying: String? {
        get { defaults.string(forKey: "nowPlaying") }
        set { defaults.set(newValue, forKey: "nowPlaying") }
    }

    static var favourites: [Int] {
        get { defaults.array(forKey: "favourites") as? [Int] ?? [] }
        set { defaults.set(newValue, forKey: "favourites") }
    }

    /// Most recently played first.
    static var recents: [Int] {
        get { defaults.array(forKey: "recents") as? [Int] ?? [] }
        set { defaults.set(Array(newValue.prefix(12)), forKey: "recents") }
    }

    static var current: Station? {
        guard let id = currentId else { return nil }
        return stations.first { $0.id == id }
    }

    /// Stations for the widget's buttons: favourites, then recently played, then the rest in list order.
    static func shortlist(_ count: Int) -> [Station] {
        let all = stations
        var ids: [Int] = []
        for id in favourites + recents + all.map(\.id) where !ids.contains(id) {
            ids.append(id)
        }
        return ids.compactMap { id in all.first { $0.id == id } }.prefix(count).map { $0 }
    }
}
