import AppIntents
import SwiftUI
import WidgetKit

struct RadioEntry: TimelineEntry {
    let date: Date
    let current: Station?
    let state: String
    let nowPlaying: String?
    let shortlist: [Station]

    var isOn: Bool { state == "playing" || state == "connecting" }

    static func now() -> RadioEntry {
        RadioEntry(date: Date(), current: Shared.current ?? Shared.stations.first, state: Shared.state,
                   nowPlaying: Shared.nowPlaying, shortlist: Shared.shortlist(12))
    }
}

/// The app reloads the widget whenever something changes, so one entry is enough.
struct RadioProvider: TimelineProvider {
    func placeholder(in context: Context) -> RadioEntry { .now() }

    func getSnapshot(in context: Context, completion: @escaping (RadioEntry) -> Void) {
        completion(.now())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadioEntry>) -> Void) {
        completion(Timeline(entries: [.now()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

@main
struct RadioWidgetBundle: WidgetBundle {
    var body: some Widget {
        RadioWidget()
    }
}

struct RadioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DriveRadio", provider: RadioProvider()) { entry in
            RadioWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Drive Radio")
        .description("Sri Lankan radio stations. Favourites from the menu bar app come first.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

enum Theme {
    static let accent = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let background = LinearGradient(colors: [Color(red: 0.13, green: 0.12, blue: 0.2), Color(red: 0.06, green: 0.06, blue: 0.1)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct RadioWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RadioEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Sizes

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            stationInfo(nameSize: 17)
            Spacer(minLength: 6)
            controls(big: 34)
        }
    }

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 4)
                stationInfo(nameSize: 17)
                Spacer(minLength: 6)
                controls(big: 34)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            grid(Array(entry.shortlist.prefix(6)), columns: 2, height: 26)
                .frame(maxWidth: .infinity)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .bottom) {
                stationInfo(nameSize: 22)
                Spacer(minLength: 8)
                controls(big: 40)
            }
            Spacer(minLength: 0)
            grid(Array(entry.shortlist.prefix(12)), columns: 3, height: 40)
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(Theme.accent)
            Text("DRIVE RADIO")
                .tracking(0.8)
            Spacer(minLength: 0)
            if entry.state == "playing" {
                Text("LIVE")
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.white.opacity(0.75))
    }

    private func stationInfo(nameSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.current?.name ?? "No station")
                .font(.system(size: nameSize, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(entry.state == "failed" ? Color.red.opacity(0.9) : .white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var status: String {
        switch entry.state {
        case "connecting": return "Connecting…"
        case "failed": return "Not reachable"
        case "playing": return entry.nowPlaying ?? entry.current?.subtitle ?? "Live"
        default: return entry.current?.subtitle.isEmpty == false ? entry.current!.subtitle : "Stopped"
        }
    }

    private func controls(big: CGFloat) -> some View {
        HStack(spacing: 10) {
            Button(intent: PreviousStationIntent()) {
                Image(systemName: "backward.fill").font(.system(size: big * 0.38))
            }
            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: entry.isOn ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: big))
                    .foregroundStyle(.white, Theme.accent)
            }
            Button(intent: NextStationIntent()) {
                Image(systemName: "forward.fill").font(.system(size: big * 0.38))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
    }

    private func grid(_ stations: [Station], columns: Int, height: CGFloat) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: columns)
        return LazyVGrid(columns: cols, spacing: height > 30 ? 8 : 6) {
            ForEach(stations) { s in
                let on = s.id == entry.current?.id && entry.isOn
                Button(intent: PlayStationIntent(stationId: s.id)) {
                    HStack(spacing: 4) {
                        if on {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 8))
                        }
                        Text(s.name)
                            .font(.system(size: height > 30 ? 12 : 11, weight: on ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: height)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.accent : Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
