import Testing
import WingspotCore

private func badge(levels: [Int], level: Int) -> BadgeProgress {
    BadgeProgress(
        id: "b", name: .init(["en": "B"]), category: "milestones", levels: levels, value: 0, level: level
    )
}

@Test func allShowsEveryBadge() {
    #expect(BadgeFilter.all.matches(badge(levels: [1, 5], level: 0)))
    #expect(BadgeFilter.all.matches(badge(levels: [1, 5], level: 2)))
}

@Test func earnedNeedsAtLeastOneLevel() {
    #expect(!BadgeFilter.earned.matches(badge(levels: [1, 5], level: 0)))
    #expect(BadgeFilter.earned.matches(badge(levels: [1, 5], level: 1)))
    #expect(BadgeFilter.earned.matches(badge(levels: [1], level: 1)))
}

@Test func inProgressMeansLevelsAreLeft() {
    #expect(BadgeFilter.inProgress.matches(badge(levels: [1, 5], level: 0)))
    #expect(BadgeFilter.inProgress.matches(badge(levels: [1, 5], level: 1)))
    #expect(!BadgeFilter.inProgress.matches(badge(levels: [1, 5], level: 2)))
    #expect(!BadgeFilter.inProgress.matches(badge(levels: [1], level: 1)))
}
