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
}
