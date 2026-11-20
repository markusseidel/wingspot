import Account
import SwiftUI

/// The friends leaderboard: loads the board and your own switch for being on other people's boards.
@MainActor
@Observable
final class LeaderboardStore {
    private let backend: any LeaderboardBackend

    init(backend: any LeaderboardBackend) {
        self.backend = backend
    }

    func rows(_ metric: LeaderboardMetric, _ period: LeaderboardPeriod) async throws -> [LeaderboardRow] {
        try await backend.leaderboard(metric: metric, period: period)
    }

    func shown(of me: UUID) async -> Bool {
        (try? await backend.showsOnLeaderboard(of: me)) ?? false
    }

    func setShown(_ shown: Bool, as me: UUID) async -> Bool {
        do {
            try await backend.setShowsOnLeaderboard(shown, as: me)
            return true
        } catch {
            return false
        }
    }
}

/// You and the people you follow, ranked. Only people who switched it on are on it.
struct LeaderboardView: View {
    @Environment(LeaderboardStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var metric = LeaderboardMetric.distance
    @State private var period = LeaderboardPeriod.year
    @State private var rows: [LeaderboardRow] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var shown = false
    @State private var shownLoaded = false

    var body: some View {
        List {
            Section {
                Picker("Ranked by", selection: $metric) {
                    Text("Distance").tag(LeaderboardMetric.distance)
                    Text("Flights").tag(LeaderboardMetric.flights)
                    Text("Countries").tag(LeaderboardMetric.countries)
                    Text("Airports").tag(LeaderboardMetric.airports)
                }
                .pickerStyle(.segmented)
                Picker("Period", selection: $period) {
                    Text("This year").tag(LeaderboardPeriod.year)
                    Text("All time").tag(LeaderboardPeriod.all)
                }
                .pickerStyle(.segmented)
            }
            if failed {
                Section { Label("Couldn't load the leaderboard", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
            } else if loaded {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.headline.monospacedDigit()).frame(width: 28)
                            AvatarView(id: row.userID, name: row.name, size: 36)
                            Text(verbatim: row.isMe ? String(localized: "You") : row.name)
                                .font(row.isMe ? .body.bold() : .body)
                            Spacer()
                            Text(valueText(row.value)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .listRowBackground(row.isMe ? Color.accentColor.opacity(0.1) : nil)
                    }
                } footer: {
                    if rows.count <= 1 {
                        Text("Only people you follow who switched on \"Show me on friends' leaderboards\" appear here.")
                    }
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
            if shownLoaded {
                Section {
                    Toggle("Show me on friends' leaderboards", isOn: Binding(get: { shown }, set: { change($0) }))
                } footer: {
                    Text("Friends who follow you can then see you on their board, counting only the check-ins they may see. Off by default.")
                }
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(metric.rawValue)-\(period.rawValue)") { await load() }
        .task {
            if let me = account.userID {
                shown = await store.shown(of: me)
                shownLoaded = true
            }
        }
    }

    private func valueText(_ value: Int) -> String {
        metric == .distance ? "\(value.formatted()) km" : value.formatted()
    }

    private func load() async {
        do {
            rows = try await store.rows(metric, period)
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }

    private func change(_ on: Bool) {
        guard let me = account.userID else { return }
        shown = on
        Task {
            if await !store.setShown(on, as: me) { shown = !on }
        }
    }
}
