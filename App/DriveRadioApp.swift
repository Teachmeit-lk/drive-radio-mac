import AppKit
import ServiceManagement
import SwiftUI

/// Menu bar radio for the Drive Launcher station list. The desktop / Notification Centre widget sends its
/// button presses here, because a widget can't play sound itself.
@main
struct DriveRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var player = Player.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(player)
        } label: {
            Image(systemName: player.state == .playing ? "dot.radiowaves.left.and.right" : "radio")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let player = Player.shared
            RadioCommand.handler = { player.handle($0) }
            // the widget launched us to run a button press
            player.runPendingCommand(maxAge: 30)
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            Task { @MainActor in Player.shared.runPendingCommand(maxAge: 30) }
        }, Shared.commandNotification as CFString, nil, .deliverImmediately)

        Task { @MainActor in
            await Player.shared.refreshStations()
            // keep the list fresh while the app stays open
            while true {
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
                await Player.shared.refreshStations()
            }
        }
    }
}

enum LaunchAtLogin {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}
