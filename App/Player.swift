import AVFoundation
import Combine
import MediaPlayer
import WidgetKit

/// Plays one station at a time with AVPlayer (it handles the MP3, AAC and Shoutcast streams), keeps the shared
/// state for the widget, and answers the media keys and Control Center's Now Playing.
@MainActor
final class Player: NSObject, ObservableObject, AVPlayerItemMetadataOutputPushDelegate {
    static let shared = Player()

    enum State: String { case stopped, connecting, playing, failed }

    @Published private(set) var stations: [Station] = Shared.stations
    @Published private(set) var current: Station? = Shared.current
    @Published private(set) var state: State = .stopped
    @Published private(set) var nowPlaying: String?
    @Published private(set) var favourites: [Int] = Shared.favourites
    @Published var volume: Float = Shared.defaults.object(forKey: "volume") as? Float ?? 1 {
        didSet {
            player.volume = volume
            Shared.defaults.set(volume, forKey: "volume")
        }
    }

    private let player = AVPlayer()
    private var observers: [NSKeyValueObservation] = []
    private var itemObservers: [NSObjectProtocol] = []
    private var retries = 0
    private var retryTask: Task<Void, Never>?
    private var lastCommandAt: Double = 0

    override init() {
        super.init()
        player.volume = volume
        observers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in self?.timeControlChanged(p.timeControlStatus) }
        })
        setUpRemoteCommands()
        publish()
    }

    // MARK: Commands

    func handle(_ command: RadioCommand) {
        switch command {
        case .play(let id):
            if let s = stations.first(where: { $0.id == id }) { play(s) }
        case .toggle: toggle()
        case .next: step(1)
        case .previous: step(-1)
        }
    }

    /// A command the widget left in the shared defaults (each is run once).
    func runPendingCommand(maxAge: TimeInterval) {
        guard let d = Shared.defaults.dictionary(forKey: "command"),
              let at = d["at"] as? Double, at != lastCommandAt else { return }
        lastCommandAt = at
        Shared.defaults.removeObject(forKey: "command")
        guard Date().timeIntervalSince1970 - at < maxAge, let command = RadioCommand(dictionary: d) else { return }
        handle(command)
    }

    func play(_ station: Station) {
        current = station
        retries = 0
        Shared.recents = [station.id] + Shared.recents.filter { $0 != station.id }
        start()
    }

    func toggle() {
        if state == .stopped || state == .failed {
            if let s = current ?? stations.first { play(s) }
        } else {
            stop()
        }
    }

    func stop() {
        retryTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .stopped
        nowPlaying = nil
        publish()
    }

    func step(_ by: Int) {
        guard !stations.isEmpty else { return }
        let i = stations.firstIndex { $0.id == current?.id } ?? -by
        play(stations[(i + by + stations.count) % stations.count])
    }

    func toggleFavourite(_ station: Station) {
        if favourites.contains(station.id) {
            favourites.removeAll { $0 == station.id }
        } else {
            favourites.append(station.id)
        }
        Shared.favourites = favourites
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Station list

    /// Fetch the list from the Drive Launcher server at most every 6 hours (or now, when forced).
    func refreshStations(force: Bool = false) async {
        if !force, let at = Shared.stationsFetched, Date().timeIntervalSince(at) < 6 * 3600 { return }
        var req = URLRequest(url: Shared.api, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(#"{"client":"mac"}"#.utf8)
        struct Reply: Decodable { let ok: Bool; let stations: [Station] }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.ok, !reply.stations.isEmpty else { return }
        Shared.save(stations: reply.stations)
        stations = reply.stations
        if let id = current?.id { current = stations.first { $0.id == id } ?? current }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Playback

    private func start() {
        retryTask?.cancel()
        itemObservers.forEach(NotificationCenter.default.removeObserver)
        itemObservers = []
        guard let s = current, let url = URL(string: s.url) else { return }
        state = .connecting
        nowPlaying = nil

        let item = AVPlayerItem(url: url)
        let meta = AVPlayerItemMetadataOutput(identifiers: nil)
        meta.setDelegate(self, queue: .main)
        item.add(meta)
        observers = Array(observers.prefix(1))   // keep the player's own observer
        observers.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in if item.status == .failed { self?.retry() } }
        })
        for name in [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.didPlayToEndTimeNotification] {
            itemObservers.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.retry() }   // a live stream never ends on its own
            })
        }
        player.replaceCurrentItem(with: item)
        player.play()
        publish()
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        guard player.currentItem != nil, state != .stopped else { return }
        if status == .playing {
            state = .playing
            retries = 0
        } else if status == .waitingToPlayAtSpecifiedRate {
            state = .connecting
        }
        publish()
    }

    /// Dropped or failed stream: try again, waiting a little longer each time, then give up.
    private func retry() {
        guard state != .stopped else { return }
        retries += 1
        if retries > 5 {
            player.replaceCurrentItem(with: nil)
            state = .failed
            publish()
            return
        }
        state = .connecting
        publish()
        let wait = UInt64(min(2 * retries, 8)) * 1_000_000_000
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        let item = groups.flatMap(\.items).first {
            $0.identifier?.rawValue == "icy/StreamTitle" || $0.commonKey == .commonKeyTitle
        }
        Task { @MainActor [weak self] in
            let text = (try? await item?.load(.stringValue)) ?? nil
            let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-")))
            // some encoders send their own advert instead of the song
            let advert = clean.map { $0.localizedCaseInsensitiveContains("powered by") || $0.contains("www.") || $0.contains("http") } ?? true
            self?.nowPlaying = clean?.isEmpty == false && !advert ? clean : nil
            self?.publish()
        }
    }

    // MARK: Shared state, widget, Now Playing

    private func publish() {
        let changed = Shared.currentId != current?.id || Shared.state != state.rawValue || Shared.nowPlaying != nowPlaying
        Shared.currentId = current?.id
        Shared.state = state.rawValue
        Shared.nowPlaying = nowPlaying
        if changed { WidgetCenter.shared.reloadAllTimelines() }

        let center = MPNowPlayingInfoCenter.default()
        if let s = current, state != .stopped {
            center.nowPlayingInfo = [
                MPMediaItemPropertyTitle: nowPlaying ?? s.name,
                MPMediaItemPropertyArtist: s.name,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            ]
            center.playbackState = state == .playing ? .playing : .interrupted
        } else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
        }
    }

    private func setUpRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.state == .stopped || self?.state == .failed { self?.toggle() } }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        c.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.step(1) }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.step(-1) }
            return .success
        }
    }
}
