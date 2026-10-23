import SwiftUI

/// The menu bar window: what's playing, controls, and the station list with language filter and favourites.
struct MenuView: View {
    @EnvironmentObject private var player: Player
    @State private var language = "All"
    @State private var search = ""
    @State private var launchAtLogin = LaunchAtLogin.isOn

    private let languages = ["All", "★", "Sinhala", "Tamil", "English", "Mixed"]

    private var shown: [Station] {
        player.stations.filter { s in
            (language == "All" || (language == "★" ? player.favourites.contains(s.id) : s.language == language))
                && (search.isEmpty || s.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            nowPlaying
                .padding(14)
            Divider()
            filters
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            list
            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 340, height: 520)
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: player.state == .playing)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.name ?? "Drive Radio")
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(player.state == .failed ? .red : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                Button { player.step(-1) } label: { Image(systemName: "backward.fill") }
                Button { player.toggle() } label: {
                    Image(systemName: player.state == .stopped || player.state == .failed ? "play.circle.fill" : "stop.circle.fill")
                        .font(.system(size: 30))
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { player.step(1) } label: { Image(systemName: "forward.fill") }
                Image(systemName: "speaker.fill").foregroundStyle(.secondary).padding(.leading, 6)
                Slider(value: $player.volume, in: 0...1)
                    .controlSize(.small)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusLine: String {
        switch player.state {
        case .stopped: return player.current == nil ? "Pick a station" : "Stopped"
        case .connecting: return "Connecting…"
        case .failed: return "Station not reachable – try again later"
        case .playing: return player.nowPlaying ?? player.current?.subtitle ?? "Live"
        }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            TextField("Search stations", text: $search)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 4) {
                ForEach(languages, id: \.self) { l in
                    Button { language = l } label: {
                        Text(l)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(language == l ? Color.accentColor : Color.secondary.opacity(0.15)))
                            .foregroundStyle(language == l ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(shown) { s in
                    row(s)
                }
                if shown.isEmpty {
                    Text(language == "★" ? "Star a station to keep it here and on the widget." : "No stations")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func row(_ s: Station) -> some View {
        let isCurrent = player.current?.id == s.id && player.state != .stopped
        return HStack(spacing: 10) {
            Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                .font(.caption)
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).fontWeight(isCurrent ? .semibold : .regular)
                if !s.subtitle.isEmpty {
                    Text(s.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { player.toggleFavourite(s) } label: {
                Image(systemName: player.favourites.contains(s.id) ? "star.fill" : "star")
                    .foregroundStyle(player.favourites.contains(s.id) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Favourites come first on the widget")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? Color.accentColor.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { player.play(s) }
    }

    private var footer: some View {
        HStack {
            Toggle("Open at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
            Spacer()
            Menu {
                Button("Update station list") { Task { await player.refreshStations(force: true) } }
                Text("Add the widget: right-click the desktop → Edit Widgets → Drive Radio")
                Divider()
                Button("Quit Drive Radio") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
