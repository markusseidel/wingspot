import Account
import Foundation
import Persistence

/// Gives the restorer the person's own check-ins from the server, as the account backend returns them.
struct AccountCheckInSource: CheckInSource {
    let backend: any MyCheckInsBackend

    func myCheckIns(after cursor: (time: String, id: UUID)?, pageSize: Int) async throws -> [RemoteCheckIn] {
        try await backend.myCheckIns(after: cursor.map { FeedCursor(time: $0.time, id: $0.id) }, pageSize: pageSize).map {
            RemoteCheckIn(
                id: $0.id, kind: $0.kind, occurredAt: $0.occurredAt, cursorTime: $0.cursorTime, registration: $0.registration,
                typeICAO: $0.typeICAO, airportID: $0.airportID, airportCode: $0.airportCode, originID: $0.originID,
                destinationID: $0.destinationID, originCode: $0.originCode, destinationCode: $0.destinationCode,
                flightNumber: $0.flightNumber, cabin: $0.cabin, seat: $0.seat, visitContext: $0.visitContext,
                latitude: $0.latitude, longitude: $0.longitude, timeKnown: $0.timeKnown
            )
        }
    }
}
