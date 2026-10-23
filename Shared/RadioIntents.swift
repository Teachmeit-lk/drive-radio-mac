import AppIntents
import AppKit
import Foundation
import WidgetKit

/// What the widget's buttons (and Shortcuts) ask the player to do.
enum RadioCommand {
    case play(Int)
    case toggle
    case next
    case previous

    var dictionary: [String: Any] {
        var d: [String: Any] = ["at": Date().timeIntervalSince1970]
        switch self {
        case .play(let id): d["action"] = "play"; d["id"] = id
        case .toggle: d["action"] = "toggle"
        case .next: d["action"] = "next"
        case .previous: d["action"] = "previous"
        }
        return d
    }

    init?(dictionary d: [String: Any]) {
        switch d["action"] as? String {
        case "play": guard let id = d["id"] as? Int else { return nil }; self = .play(id)
        case "toggle": self = .toggle
        case "next": self = .next
        case "previous": self = .previous
        default: return nil
        }
    }

    /// Set by the app at launch; nil inside the widget extension.
    @MainActor static var handler: ((RadioCommand) -> Void)?

    /// Run the command in the app. From the widget: leave it in the shared defaults, wake the app with a Darwin
    /// notification, or launch the app (it picks the command up at start).
    @MainActor static func send(_ command: RadioCommand) {
        if let handler {
            handler(command)
            return
        }
        Shared.defaults.set(command.dictionary, forKey: "command")
        showOptimistically(command)
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "lk.semicolon.driveradio").isEmpty
        if running {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFNotificationName(Shared.commandNotification as CFString), nil, nil, true)
        } else {
            // the widget lives in Drive Radio.app/Contents/PlugIns/DriveRadioWidget.appex
            let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: app, configuration: config)
        }
    }

    /// The widget redraws as soon as the intent returns, before the app has answered: show the expected state.
    @MainActor private static func showOptimistically(_ command: RadioCommand) {
        let list = Shared.stations
        func step(_ by: Int) {
            guard !list.isEmpty else { return }
            let i = list.firstIndex { $0.id == Shared.currentId } ?? -by
            Shared.currentId = list[(i + by + list.count) % list.count].id
            Shared.state = "connecting"
        }
        switch command {
        case .play(let id):
            Shared.currentId = id
            Shared.state = "connecting"
        case .toggle:
            Shared.state = Shared.state == "stopped" || Shared.state == "failed" ? "connecting" : "stopped"
            if Shared.currentId == nil { Shared.currentId = list.first?.id }
        case .next: step(1)
        case .previous: step(-1)
        }
        Shared.nowPlaying = nil
    }
}

struct PlayStationIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play a radio station"
    static var description = IntentDescription("Plays a Sri Lankan radio station in Drive Radio.")

    @Parameter(title: "Station ID")
    var stationId: Int

    init() {}
    init(stationId: Int) { self.stationId = stationId }

    @MainActor
    func perform() async throws -> some IntentResult {
        RadioCommand.send(.play(stationId))
        return .result()
    }
}

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or stop the radio"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RadioCommand.send(.toggle)
        return .result()
    }
}

struct NextStationIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next radio station"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RadioCommand.send(.next)
        return .result()
    }
}

struct PreviousStationIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous radio station"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RadioCommand.send(.previous)
        return .result()
    }
}
