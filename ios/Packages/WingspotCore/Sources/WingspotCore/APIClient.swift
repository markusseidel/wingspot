import Foundation

/// The `Config` schema in contracts/openapi.yaml. Unknown fields are ignored, as the contract requires.
public struct RemoteConfig: Decodable, Equatable, Sendable {
    public struct MinimumVersion: Decodable, Equatable, Sendable {
        public let ios: String
        public let android: String
    }

    public let minimumVersion: MinimumVersion
    /// A missing flag counts as disabled.
    public let featureFlags: [String: Bool]

    private enum CodingKeys: String, CodingKey {
        case minimumVersion = "min_version"
        case featureFlags = "feature_flags"
    }
}

/// The `RefdataManifest` schema in contracts/openapi.yaml.
public struct RefdataManifest: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let dataVersion: String
    public let url: URL
    public let sha256: String
    public let sizeBytes: Int

    public init(schemaVersion: Int, dataVersion: String, url: URL, sha256: String, sizeBytes: Int) {
        self.schemaVersion = schemaVersion
        self.dataVersion = dataVersion
        self.url = url
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case dataVersion = "data_version"
        case url, sha256
        case sizeBytes = "size_bytes"
    }
}

/// One check-in in `POST /v1/checkins` (`CheckinItem` in contracts/openapi.yaml).
public struct CheckInUploadItem: Encodable, Equatable, Sendable {
    public let id: UUID
    public let kind: String
    public let occurredAt: Date
    public let registration: String?
    public let typeICAO: String?
    public let airportID: Int?
    public let latitude: Double?
    public let longitude: Double?
    /// Why the user was at the airport. Only for airport check-ins.
    public let context: String?
    /// Flown check-ins only.
    public let originID: Int?
    public let destinationID: Int?
    public let flightNumber: String?
    public let cabin: String?
    public let seat: String?
    /// Sent explicitly, so what the app means doesn't depend on the server's default.
    public let visibility: String

    public init(
        id: UUID, kind: String, occurredAt: Date, registration: String?, typeICAO: String?, airportID: Int?,
        latitude: Double?, longitude: Double?, context: String? = nil,
        originID: Int? = nil, destinationID: Int? = nil, flightNumber: String? = nil, cabin: String? = nil,
        seat: String? = nil, visibility: String = "private"
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.registration = registration
        self.typeICAO = typeICAO
        self.airportID = airportID
        self.latitude = latitude
        self.longitude = longitude
        self.context = context
        self.originID = originID
        self.destinationID = destinationID
        self.flightNumber = flightNumber
        self.cabin = cabin
        self.seat = seat
        self.visibility = visibility
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind
        case occurredAt = "occurred_at"
        case registration
        case typeICAO = "type_icao"
        case airportID = "airport_id"
        case latitude, longitude, context
        case originID = "origin_id"
        case destinationID = "destination_id"
        case flightNumber = "flight_number"
        case cabin, seat, visibility
    }
}

/// One result in the answer to `POST /v1/checkins` (`CheckinResult` in contracts/openapi.yaml).
public struct CheckInUploadResult: Decodable, Equatable, Sendable {
    public let id: UUID
    /// `stored` or `rejected`. Any other value is a status this app doesn't know, which is neither.
    public let status: String
    public let code: String?

    public init(id: UUID, status: String, code: String? = nil) {
        self.id = id
        self.status = status
        self.code = code
    }

    public var isStored: Bool { status == "stored" }
    public var isRejected: Bool { status == "rejected" }
}

/// The server's answer for one photo (`PUT /v1/checkins/{id}/photos/{id}`).
public enum PhotoUploadOutcome: Equatable, Sendable {
    case stored
    /// The server refused it for good, with its code, such as `too_many_photos`. Uploading again gets the same answer.
    case rejected(code: String)
    /// The check-in isn't on the server yet. The photo waits and goes up after it.
    case checkInNotThereYet
}

public enum APIError: Error, Equatable {
    case unexpectedStatus(Int)
}

/// Client for the Wingspot API (contracts/openapi.yaml).
public struct APIClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let transport: Transport

    public init(
        baseURL: URL,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// `PUT /v1/checkins/{checkinID}/photos/{photoID}`. The body is the JPEG, which must have no metadata.
    /// Repeating it is safe, because the server stores each photo id once.
    /// - Throws: for anything that should be tried again later, such as no network or a server error.
    public func uploadPhoto(
        checkInID: UUID, photoID: UUID, jpeg: Data, accessToken: String
    ) async throws -> PhotoUploadOutcome {
        var request = URLRequest(url: baseURL.appending(path: "v1/checkins/\(checkInID.uuidString.lowercased())/photos/\(photoID.uuidString.lowercased())"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg

        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.code
        switch status {
        case 200: return .stored
        case 404 where code == "unknown_checkin": return .checkInNotThereYet
        case 400, 409, 413, 415: return .rejected(code: code ?? "http_\(status)")
        default: throw APIError.unexpectedStatus(status)
        }
    }

    private struct ErrorBody: Decodable { let code: String? }

    /// `GET /v1/config`. Public, because apps must check their minimum version before sign-in.
    public func config() async throws -> RemoteConfig {
        let request = URLRequest(url: baseURL.appending(path: "v1/config"))
        let (data, response) = try await transport(request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw APIError.unexpectedStatus(status)
        }
        return try JSONDecoder().decode(RemoteConfig.self, from: data)
    }

    /// `GET /v1/refdata/manifest`. Returns `nil` if no snapshot has been published yet.
    public func refdataManifest() async throws -> RefdataManifest? {
        let request = URLRequest(url: baseURL.appending(path: "v1/refdata/manifest"))
        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 404 { return nil }
        if status != 200 { throw APIError.unexpectedStatus(status) }
        return try JSONDecoder().decode(RefdataManifest.self, from: data)
    }

    /// `POST /v1/checkins`. Safe to repeat: the server answers `stored` again for an id it already has.
    /// - Throws: `APIError.unexpectedStatus` for any answer other than 200, and `URLError` without a network.
    public func uploadCheckins(_ items: [CheckInUploadItem], accessToken: String) async throws -> [CheckInUploadResult] {
        struct Body: Encodable { let checkins: [CheckInUploadItem] }
        struct Answer: Decodable { let results: [CheckInUploadResult] }

        var request = URLRequest(url: baseURL.appending(path: "v1/checkins"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        request.httpBody = try encoder.encode(Body(checkins: items))

        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else { throw APIError.unexpectedStatus(status) }
        return try JSONDecoder().decode(Answer.self, from: data).results
    }

    /// `GET /v1/me/progress`. Returns the raw answer too, so the app can keep it for offline use.
    public func progress(accessToken: String) async throws -> (progress: UserProgress, raw: Data) {
        var request = URLRequest(url: baseURL.appending(path: "v1/me/progress"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else { throw APIError.unexpectedStatus(status) }
        return (try UserProgress.decode(data), data)
    }
}
