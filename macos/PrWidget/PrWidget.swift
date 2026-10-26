import AppIntents
import SwiftUI
import WidgetKit

// Widgets for pinned pull requests. The app writes a JSON snapshot per PR,
// the pinned list and the recent PRs (see Runner/WidgetChannel.swift), then
// asks WidgetKit to reload. Clicking a widget opens the PR's pr:// link,
// which resumes reading where it stopped.

struct PrSnapshot: Codable {
  var title: String
  var state: String
  var repo: String
  var number: Int
  var author: String
  var viewed: Int
  var files: Int
  var additions: Int
  var deletions: Int
  var comments: Int
  var reading: String?

  static let sample = PrSnapshot(
    title: "Move the renderer to an explicit pipeline", state: "open", repo: "acme/engine", number: 4242,
    author: "mona", viewed: 48, files: 120, additions: 2400, deletions: 830, comments: 6,
    reading: "render/pipeline.dart")

  /// A recent PR the app hasn't saved a snapshot for yet: only its title
  /// and state are known until it's opened again.
  static func partial(_ key: String) -> PrSnapshot? {
    let parts = key.split(separator: "#", maxSplits: 1)
    guard parts.count == 2, let number = Int(parts[1]) else { return nil }
    let recent = Store.recentInfo[key]
    return PrSnapshot(
      title: recent?["title"] ?? key, state: recent?["state"] ?? "open", repo: String(parts[0]), number: number,
      author: "", viewed: 0, files: 0, additions: 0, deletions: 0, comments: 0, reading: nil)
  }

  var loaded: Bool { files > 0 }

  /// "engine #4242". String(number) keeps it from being formatted as 4.242.
  var shortRef: String { "\((repo as NSString).lastPathComponent) #\(String(number))" }
  var url: URL? { URL(string: "pr://github.com/\(repo)/pull/\(number)") }
  var progress: Double { files == 0 ? 0 : min(1, Double(viewed) / Double(files)) }
}

enum Store {
  static let defaults: UserDefaults? = {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "PRReaderAppGroup") as? String else { return nil }
    return UserDefaults(suiteName: group)
  }()

  /// The app's copy outside the containers, readable when the App Group
  /// isn't (ad-hoc signing). See Runner/WidgetChannel.swift.
  static var exported: [String: Any] {
    let home = getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    let url = URL(fileURLWithPath: home)
      .appendingPathComponent("Library/Application Support/de.reonic.prReader.widgets/widgets.json")
    guard let data = try? Data(contentsOf: url) else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
  }

  private static func value(_ key: String) -> Any? {
    defaults?.object(forKey: key) ?? exported[key]
  }

  static func snapshot(_ key: String) -> PrSnapshot? {
    guard let json = value("snap:\(key)") as? String, let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(PrSnapshot.self, from: data)
  }

  /// Title and state of each recent PR, by key.
  static var recentInfo: [String: [String: String]] { value("recentInfo") as? [String: [String: String]] ?? [:] }

  /// The full snapshot, or what is known from the recents list.
  static func best(_ key: String) -> PrSnapshot? { snapshot(key) ?? .partial(key) }

  static var pinned: [String] { value("pinned") as? [String] ?? [] }
  static var recents: [String] { value("recents") as? [String] ?? [] }

  /// Pinned PRs first, then recent ones, without duplicates.
  static var choices: [String] {
    var seen = Set<String>()
    return (pinned + recents).filter { seen.insert($0).inserted }
  }

}

// MARK: - Choosing the PR (Edit Widget)

struct PrEntity: AppEntity {
  let id: String
  let title: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Pull request"
  static var defaultQuery = PrQuery()

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
  }

  let subtitle: String

  init(key: String) {
    id = key
    let snap = Store.best(key)
    title = snap?.title ?? key
    subtitle = snap.map { "\($0.repo) #\(String($0.number)) · \($0.state.capitalized)" } ?? key
  }
}

struct PrQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [PrEntity] {
    identifiers.map(PrEntity.init(key:))
  }

  func suggestedEntities() async throws -> [PrEntity] {
    let keys = Store.choices
    return keys.map(PrEntity.init(key:))
  }

  func entities(matching string: String) async throws -> [PrEntity] {
    try await suggestedEntities().filter {
      $0.title.localizedCaseInsensitiveContains(string) || $0.id.localizedCaseInsensitiveContains(string)
    }
  }

  func defaultResult() async -> PrEntity? {
    Store.choices.first.map(PrEntity.init(key:))
  }
}

struct SelectPrIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Pull request"
  static var description = IntentDescription("Choose a pinned or recent pull request.")

  @Parameter(title: "Pull request")
  var pr: PrEntity?
}

// MARK: - Timelines

struct PrEntry: TimelineEntry {
  let date: Date
  let snap: PrSnapshot?
}

struct PrProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> PrEntry { PrEntry(date: .now, snap: .sample) }

  func snapshot(for intent: SelectPrIntent, in context: Context) async -> PrEntry {
    context.isPreview && resolve(intent) == nil ? PrEntry(date: .now, snap: .sample) : PrEntry(date: .now, snap: resolve(intent))
  }

  func timeline(for intent: SelectPrIntent, in context: Context) async -> Timeline<PrEntry> {
    // The app reloads widgets whenever it saves new data.
    Timeline(entries: [PrEntry(date: .now, snap: resolve(intent))], policy: .never)
  }

  private func resolve(_ intent: SelectPrIntent) -> PrSnapshot? {
    let key = intent.pr?.id ?? Store.choices.first
    return key.flatMap(Store.best)
  }
}

struct PinnedEntry: TimelineEntry {
  let date: Date
  let prs: [PrSnapshot]
}

struct PinnedProvider: TimelineProvider {
  func placeholder(in context: Context) -> PinnedEntry { PinnedEntry(date: .now, prs: [.sample, .sample]) }

  func getSnapshot(in context: Context, completion: @escaping (PinnedEntry) -> Void) {
    let prs = load()
    completion(PinnedEntry(date: .now, prs: prs.isEmpty && context.isPreview ? [.sample, .sample] : prs))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedEntry>) -> Void) {
    completion(Timeline(entries: [PinnedEntry(date: .now, prs: load())], policy: .never))
  }

  private func load() -> [PrSnapshot] { Store.pinned.compactMap(Store.best) }
}

// MARK: - Views

extension PrSnapshot {
  var stateColor: Color {
    switch state {
    case "draft": Color(red: 0.43, green: 0.47, blue: 0.51)
    case "merged": Color(red: 0.51, green: 0.31, blue: 0.87)
    case "closed": Color(red: 0.81, green: 0.13, blue: 0.18)
    default: Color(red: 0.12, green: 0.53, blue: 0.24)
    }
  }
}

func compact(_ n: Int) -> String {
  if n >= 10_000 { return "\(n / 1000)k" }
  if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".0k", with: "k") }
  return "\(n)"
}

struct StateChip: View {
  let snap: PrSnapshot
  var body: some View {
    Text(snap.state.capitalized)
      .font(.caption2.weight(.bold))
      .foregroundStyle(.white)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(snap.stateColor, in: Capsule())
  }
}

struct ViewedLine: View {
  let snap: PrSnapshot
  var short = false
  var body: some View {
    if !snap.loaded {
      Text("Open to load progress")
    } else if snap.viewed >= snap.files {
      Text("All \(compact(snap.files)) viewed")
    } else if short {
      Text("\(compact(snap.viewed))/\(compact(snap.files)) viewed")
    } else {
      Text("\(compact(snap.viewed)) of \(compact(snap.files)) files viewed")
    }
  }
}

struct ProgressBar: View {
  let value: Double
  var body: some View {
    Capsule()
      .fill(Color.accentColor.opacity(0.2))
      .overlay(alignment: .leading) {
        GeometryReader { g in
          Capsule().fill(Color.accentColor).frame(width: value > 0 ? max(6, g.size.width * value) : 0)
        }
      }
      .frame(height: 6)
  }
}

struct DiffSize: View {
  let snap: PrSnapshot
  var body: some View {
    HStack(spacing: 4) {
      Text("+\(compact(snap.additions))").foregroundStyle(.green)
      Text("\u{2212}\(compact(snap.deletions))").foregroundStyle(.red)
    }
    .bold()
  }
}

struct PrWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: PrEntry

  var body: some View {
    if let snap = entry.snap {
      let small = family == .systemSmall
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          StateChip(snap: snap)
          Text(small ? (snap.repo as NSString).lastPathComponent : "\(snap.repo) #\(String(snap.number))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Text(snap.title)
          .font(small ? .subheadline.weight(.semibold) : .headline)
          .lineLimit(family == .systemLarge ? 6 : 3)
        Spacer(minLength: 0)
        if snap.loaded {
          ProgressBar(value: snap.progress)
        }
        HStack(spacing: 4) {
          ViewedLine(snap: snap, short: small).foregroundStyle(.secondary)
          Spacer(minLength: 2)
          if snap.loaded { DiffSize(snap: snap) }
        }
        .font(small ? .caption2 : .caption)
        .lineLimit(1)
        if let reading = snap.reading {
          Text("Continue at \((reading as NSString).lastPathComponent)")
            .font(small ? .caption2 : .caption)
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .widgetURL(snap.url)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        Text("PR Reader").font(.headline)
        Text("Open a pull request in PR Reader and choose Pin as widget to show it here.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct PinnedListView: View {
  @Environment(\.widgetFamily) var family
  let entry: PinnedEntry

  var body: some View {
    let rows = Array(entry.prs.prefix(family == .systemLarge ? 5 : 2))
    VStack(alignment: .leading, spacing: 10) {
      Text("Pinned pull requests").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      if rows.isEmpty {
        Text("Choose Pin as widget on a pull request in PR Reader.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ForEach(Array(rows.enumerated()), id: \.offset) { _, snap in
        Link(destination: snap.url ?? URL(string: "pr://")!) {
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Circle().fill(snap.stateColor).frame(width: 7, height: 7)
              Text(snap.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            HStack(spacing: 8) {
              Text(snap.shortRef).lineLimit(1).truncationMode(.middle)
              Spacer(minLength: 4)
              ViewedLine(snap: snap)
              if snap.loaded { DiffSize(snap: snap) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            ProgressBar(value: snap.progress)
          }
        }
      }
      Spacer(minLength: 0)
    }
  }
}

// MARK: - Widgets

struct PinnedPrWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "PinnedPr", intent: SelectPrIntent.self, provider: PrProvider()) { entry in
      PrWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Pull request")
    .description("A pull request with your reading progress. Click to continue reading.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct PinnedListWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "PinnedList", provider: PinnedProvider()) { entry in
      PinnedListView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Pinned pull requests")
    .description("Every pull request you pinned, with reading progress.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

@main
struct PrWidgets: WidgetBundle {
  var body: some Widget {
    PinnedPrWidget()
    PinnedListWidget()
  }
}
