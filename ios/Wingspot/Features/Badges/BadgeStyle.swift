import SwiftUI
import WingspotCore

/// How a badge looks: a symbol per category, and a color that grows with the level.
enum BadgeStyle {
    static func symbol(for category: String) -> String {
        switch category {
        case "milestones": "flag.checkered"
        case "airports": "airplane.arrival"
        case "countries": "globe.europe.africa"
        case "types": "airplane"
        case "time": "clock"
        case "hidden": "sparkles"
        default: "rosette"
        }
    }

    /// Grey while locked, then bronze, silver and gold as the levels fill up.
    static func color(level: Int, of total: Int) -> Color {
        guard level > 0, total > 0 else { return .gray.opacity(0.5) }
        let fraction = Double(level) / Double(total)
        if fraction >= 1 { return .yellow }
        return fraction > 0.5 ? Color(white: 0.62) : .brown
    }

    static func color(for badge: BadgeProgress) -> Color {
        color(level: badge.level, of: badge.levels.count)
    }
}

extension Rank {
    var title: LocalizedStringResource {
        switch self {
        case .cadet: "Cadet"
        case .studentPilot: "Student Pilot"
        case .firstOfficer: "First Officer"
        case .captain: "Captain"
        case .seniorCaptain: "Senior Captain"
        case .chiefPilot: "Chief Pilot"
        case .ace: "Ace"
        case .legend: "Legend"
        }
    }
}

/// The badge's text in the phone's language, falling back to English.
func localized(_ text: LocalizedText?) -> String {
    text?.resolved(preferring: Locale.preferredLanguages) ?? ""
}

struct BadgeIcon: View {
    let badge: BadgeProgress
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: BadgeStyle.symbol(for: badge.category))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(BadgeStyle.color(for: badge), in: Circle())
            .accessibilityHidden(true)
    }
}
