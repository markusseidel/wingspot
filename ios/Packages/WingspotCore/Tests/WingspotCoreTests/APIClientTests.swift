import Foundation
import Testing
import WingspotCore

private let baseURL = URL(string: "https://example.com/functions")!

private func client(status: Int, body: String) -> APIClient {
    APIClient(baseURL: baseURL) { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@Test func configDecodesTheContractShape() async throws {
    let config = try await client(status: 200, body: """
    {"min_version":{"ios":"0.1.0","android":"0.2.0"},"feature_flags":{"feed":true}}
    """).config()

    #expect(config.minimumVersion.ios == "0.1.0")
    #expect(config.minimumVersion.android == "0.2.0")
    #expect(config.featureFlags == ["feed": true])
}

@Test func configIgnoresUnknownFields() async throws {
    let config = try await client(status: 200, body: """
    {"min_version":{"ios":"0.1.0","android":"0.1.0","web":"1"},"feature_flags":{},"new_field":1}
    """).config()

    #expect(config.featureFlags.isEmpty)
}

@Test func configRequestsTheContractPath() async throws {
    let client = APIClient(baseURL: baseURL) { request in
        #expect(request.url?.absoluteString == "https://example.com/functions/v1/config")
        #expect(request.httpMethod == "GET")
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }

    await #expect(throws: APIError.unexpectedStatus(500)) {
        try await client.config()
    }
}
