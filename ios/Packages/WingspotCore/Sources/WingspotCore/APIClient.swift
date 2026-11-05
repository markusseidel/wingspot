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
    /// Sent explicitly, so what the app means doesn't depend on the server's default.
    public let visibility: String

    public init(
        id: UUID, kind: String, occurredAt: Date, registration: String?, typeICAO: String?, airportID: Int?,
        latitude: Double?, longitude: Double?, visibility: String = "private"
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.registration = registration
        self.typeICAO = typeICAO
        self.airportID = airportID
        self.latitude = latitude
        self.longitude = longitude
        self.visibility = visibility
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind
        case occurredAt = "occurred_at"
        case registration
        case typeICAO = "type_icao"
        case airportID = "airport_id"
        case latitude, longitude, visibility
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
