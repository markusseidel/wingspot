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

private let sampleItem = CheckInUploadItem(
    id: UUID(uuidString: "0198aaaa-0000-7000-8000-000000000001")!, kind: "spotted",
    occurredAt: Date(timeIntervalSince1970: 1_800_000_000.5), registration: "D-AIMA", typeICAO: nil, airportID: 7,
    latitude: 50.03, longitude: 8.57
)

@Test func uploadSendsTheContractShapeWithTheToken() async throws {
    let client = APIClient(baseURL: baseURL) { request in
        #expect(request.url?.absoluteString == "https://example.com/functions/v1/checkins")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [[String: Any]]])
        let item = try #require(json["checkins"]?.first)
        #expect(item["id"] as? String == "0198AAAA-0000-7000-8000-000000000001")
        #expect(item["kind"] as? String == "spotted")
        #expect(item["occurred_at"] as? String == "2027-01-15T08:00:00.500Z")
        #expect(item["registration"] as? String == "D-AIMA")
        #expect(item["airport_id"] as? Int == 7)
        #expect(item["visibility"] as? String == "private")
        #expect(item["type_icao"] == nil)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"results":[{"id":"0198aaaa-0000-7000-8000-000000000001","status":"stored"}]}"#.utf8), response)
    }

    let results = try await client.uploadCheckins([sampleItem], accessToken: "token-1")

    #expect(results == [CheckInUploadResult(id: sampleItem.id, status: "stored")])
    #expect(results[0].isStored)
}

@Test func uploadReadsRejectionsAndIgnoresUnknownFields() async throws {
    let results = try await client(status: 200, body: """
    {"results":[{"id":"0198aaaa-0000-7000-8000-000000000001","status":"rejected","code":"unknown_type","extra":1}]}
    """).uploadCheckins([sampleItem], accessToken: "t")

    #expect(results == [CheckInUploadResult(id: sampleItem.id, status: "rejected", code: "unknown_type")])
    #expect(!results[0].isStored)
}

@Test func uploadFailsOnAnyStatusButOK() async {
    for status in [400, 401, 500, 503] {
        await #expect(throws: APIError.unexpectedStatus(status)) {
            _ = try await client(status: status, body: "{}").uploadCheckins([sampleItem], accessToken: "t")
        }
    }
}
