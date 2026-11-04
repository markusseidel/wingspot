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
}
