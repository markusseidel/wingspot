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

@Test func manifestDecodesTheContractShape() async throws {
    let manifest = try await client(status: 200, body: """
    {"schema_version":2,"data_version":"2026-11-04","url":"https://example.com/r.sqlite","sha256":"abc","size_bytes":12,"extra":true}
    """).refdataManifest()
    #expect(manifest == RefdataManifest(
        schemaVersion: 2, dataVersion: "2026-11-04", url: URL(string: "https://example.com/r.sqlite")!,
        sha256: "abc", sizeBytes: 12
    ))
}

@Test func noPublishedSnapshotIsNotAnError() async throws {
    let manifest = try await client(status: 404, body: "{}").refdataManifest()
    #expect(manifest == nil)
}

@Test func manifestServerErrorsThrow() async throws {
    await #expect(throws: APIError.unexpectedStatus(500)) {
        try await client(status: 500, body: "").refdataManifest()
    }
}
