import Account
import Persistence
import SwiftUI
import WingspotCore

/// The Badges tab: level and XP on top, then every badge with its progress.
struct BadgesScreen: View {
    @Environment(AccountStore.self) private var account
    @Environment(BadgeStore.self) private var badges

    private static let categoryOrder = ["milestones", "airports", "countries", "types", "time", "hidden"]

    var body: some View {
        NavigationStack {
            Group {
                if account.userID == nil {
                    ContentUnavailableView {
                        Label("Earn badges", systemImage: "rosette")
                    } description: {
                        Text("Sign in from the Profile tab, and your check-ins will earn badges.")
                    }
                } else if let progress = badges.progress {
                    list(progress)
                } else if badges.refreshFailed {
                    ContentUnavailableView {
                        Label("Couldn't load your badges", systemImage: "wifi.slash")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try again") { Task { await badges.refresh() } }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Badges")
        }
        .task(id: account.userID) { await badges.refresh() }
    }

    private func list(_ progress: UserProgress) -> some View {
        List {
            Section { LevelHeader(progress: progress) }
            ForEach(groups(progress), id: \.category) { group in
                Section {
                    ForEach(group.badges) { BadgeRow(badge: $0) }
                } header: {
                    Text(Self.title(for: group.category))
                } footer: {
                    if group.category == "hidden", progress.hiddenRemaining > 0 {
                        Text("Hidden badges left: \(progress.hiddenRemaining)")
                    }
                }
            }
            if progress.hiddenRemaining > 0, !progress.badges.contains(where: { $0.category == "hidden" }) {
                Section {
                    Label("Hidden badges left: \(progress.hiddenRemaining)", systemImage: "questionmark.diamond")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable { await badges.refresh() }
    }

    private func groups(_ progress: UserProgress) -> [(category: String, badges: [BadgeProgress])] {
        let known = Self.categoryOrder.compactMap { category -> (String, [BadgeProgress])? in
            let items = progress.badges.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
        let others = Set(progress.badges.map(\.category)).subtracting(Self.categoryOrder).sorted()
        return known + others.map { category in (category, progress.badges.filter { $0.category == category }) }
    }

    private static func title(for category: String) -> LocalizedStringKey {
        switch category {
        case "milestones": "Milestones"
        case "airports": "Airports"
        case "countries": "Countries"
        case "types": "Aircraft types"
        case "time": "Time of day"
        case "hidden": "Hidden"
        default: LocalizedStringKey(category.capitalized)
        }
    }
}

struct LevelHeader: View {
    let progress: UserProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Level \(progress.level)").font(.title2.bold())
                Text(Rank(level: progress.level).title).foregroundStyle(.secondary)
                Spacer()
                Text("\(progress.xp) XP").font(.headline.monospacedDigit())
            }
            ProgressView(value: progress.levelFraction)
                .tint(.accentColor)
            Text("\(max(0, progress.xpForNextLevel - progress.xp)) XP to level \(progress.level + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct BadgeRow: View {
    let badge: BadgeProgress

    var body: some View {
        HStack(spacing: 12) {
            BadgeIcon(badge: badge)
            VStack(alignment: .leading, spacing: 4) {
                Text(localized(badge.name)).font(.headline)
                if let description = badge.description {
                    Text(localized(description)).font(.caption).foregroundStyle(.secondary)
                }
                if let target = badge.nextTarget {
                    ProgressView(value: Double(min(badge.value, target)), total: Double(target))
                    HStack {
                        if !badge.isSingle {
                            Text("Level \(badge.level) of \(badge.levels.count)")
                        }
                        Spacer()
                        Text(verbatim: "\(badge.value) / \(target)")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                } else {
                    Label(badge.isSingle ? "Unlocked" : "All levels reached", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
