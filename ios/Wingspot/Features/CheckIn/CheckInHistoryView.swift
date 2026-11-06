import Account
import Persistence
import SwiftData
import SwiftUI

/// Everything checked in on this iPhone, newest first, with whether it has reached the server.
struct CheckInHistoryView: View {
    @Environment(AccountStore.self) private var account
    @Query(sort: \LocalCheckIn.occurredAt, order: .reverse) private var all: [LocalCheckIn]

    /// Signed in: this account's check-ins plus those made before signing in. Signed out: everything on this
    /// iPhone, because the check-ins stay here after signing out.
    private var checkIns: [LocalCheckIn] {
        guard let userID = account.userID else { return all }
        return all.filter { $0.ownerID == nil || $0.ownerID == userID }
    }

    var body: some View {
        Group {
            if checkIns.isEmpty {
                ContentUnavailableView {
                    Label("No check-ins yet", systemImage: "binoculars")
                } description: {
                    Text("Your check-ins will appear here.")
                }
            } else {
                List {
                    Section {
                        ForEach(checkIns) { CheckInRow(checkIn: $0) }
                    } footer: {
                        if checkIns.contains(where: { $0.syncState == SyncState.rejected.rawValue }) {
                            Text("Check-ins that weren't accepted stay on this iPhone.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Check-in history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CheckInRow: View {
    let checkIn: LocalCheckIn

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.system(.headline, design: .monospaced))
                if let detail {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(checkIn.occurredAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            status
        }
        .accessibilityElement(children: .combine)
    }

    /// The registration if there is one, otherwise the type.
    private var title: String {
        if checkIn.kind == "airport" { return checkIn.airportCode ?? "?" }
        if checkIn.kind == "flown" { return "\(checkIn.originCode ?? "?") → \(checkIn.destinationCode ?? "?")" }
        return checkIn.registration ?? checkIn.typeICAO ?? "?"
    }

    private var detail: String? {
        if checkIn.kind == "airport" {
            return VisitContext(rawValue: checkIn.visitContext ?? "").map { String(localized: $0.title) }
                ?? String(localized: "Airport")
        }
        if checkIn.kind == "flown" {
            let parts = [checkIn.flightNumber, checkIn.registration ?? checkIn.typeName ?? checkIn.typeICAO].compactMap { $0 }
            return parts.isEmpty ? String(localized: "Flown") : parts.joined(separator: " · ")
        }
        let type = checkIn.registration == nil ? checkIn.typeName : (checkIn.typeName ?? checkIn.typeICAO)
        let parts = [type, checkIn.airportCode].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var status: some View {
        switch SyncState(rawValue: checkIn.syncState) {
        case .synced:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.green)
                .accessibilityLabel("Uploaded")
        case .rejected:
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.red)
                .accessibilityLabel("Not accepted")
        default:
            Image(systemName: "icloud.and.arrow.up")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Waiting to upload")
        }
    }
}
