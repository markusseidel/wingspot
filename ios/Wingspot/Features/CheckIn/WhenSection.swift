import Persistence
import SwiftUI

/// The "When" part of a sighting or an airport check-in (#312): "Now" by default, or a day in the past, with a time when the person
/// knows it. A photo's capture date is offered as a tap-to-use suggestion; it never changes the row by itself.
struct WhenSection: View {
    @Binding var choice: WhenChoice
    /// The photos picked for this check-in, for the suggestion.
    var photos: [PreparedPhoto] = []
    /// During a session at a backdated visit: the choice of the visit, which the sighting starts with.
    var visit: WhenChoice?

    private var suggestion: Date? {
        guard choice.isNow else { return nil }
        return WhenChoice.suggestion(from: photos.compactMap(\.takenAt).min())
    }

    var body: some View {
        Section {
            if choice.isNow {
                Button { choice = WhenChoice(isNow: false, date: Date(), hasTime: false) } label: {
                    LabeledContent("When") {
                        HStack(spacing: 4) {
                            Text("Now")
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            } else {
                if let visit, visit == choice {
                    LabeledContent("When", value: String(localized: "Same as the visit"))
                }
                DatePicker("Date", selection: dateBinding, in: ...Date(), displayedComponents: .date)
                Toggle("Set the time", isOn: $choice.hasTime)
                if choice.hasTime {
                    DatePicker("Time", selection: dateBinding, in: ...Date(), displayedComponents: .hourAndMinute)
                }
                Button("Now") { choice = .now }
            }
            if let suggestion {
                Button { choice = WhenChoice.usingPhoto(at: suggestion) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo taken \(suggestion.formatted(date: .abbreviated, time: .shortened))")
                        Text("Use this date").font(.footnote).foregroundStyle(.tint)
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            if !choice.isNow { Text("When") }
        } footer: {
            if !choice.isNow {
                Text("Who can see this check-in is decided by its visibility, not by its date.")
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { choice.date }, set: { choice.date = WhenChoice.limit($0) })
    }
}
