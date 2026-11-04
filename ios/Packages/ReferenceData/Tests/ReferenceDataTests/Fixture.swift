import Foundation
import GRDB

/// Builds a small database from the real schema in contracts/, so these tests follow the shared contract.
enum Fixture {
    static func makeDatabase(dataVersion: String = "test-1", userVersion: Int? = nil) throws -> URL {
        let contracts = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "contracts/refdata/schema.sql")
        let schema = try String(contentsOf: contracts, encoding: .utf8)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "fixture.sqlite")

        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: schema)
            try db.execute(sql: "INSERT INTO meta VALUES ('data_version', ?)", arguments: [dataVersion])
            if let userVersion { try db.execute(sql: "PRAGMA user_version = \(userVersion)") }
            for type in [
                ("A388", "Airbus", "A380-800"), ("B738", "Boeing", "737-800"), ("B38M", "Boeing", "737 MAX 8"),
                ("CRJ9", "Bombardier", "CRJ-900"), ("EC35", "Airbus Helicopters", "EC135/H135"),
            ] {
                try db.execute(sql: "INSERT INTO aircraft_types VALUES (?, ?, ?, NULL, NULL, NULL, NULL)",
                               arguments: [type.0, type.1, type.2])
                try db.execute(sql: "INSERT INTO aircraft_types_fts (icao_code, manufacturer, model) VALUES (?, ?, ?)",
                               arguments: [type.0, type.1, type.2])
            }
            // id, icao, iata, name, city, type, latitude, longitude, default_search, keywords
            let airports: [[(any DatabaseValueConvertible)?]] = [
                [1, "LOWW", "VIE", "Vienna International Airport", "Wien", "large_airport", 48.11, 16.57, 1, "Flughafen Wien"],
                [2, "LOAN", nil, "Wiener Neustadt East", "Wien Neustadt", "small_airport", 47.84, 16.26, 0, nil],
                [3, "EDDF", "FRA", "Frankfurt am Main Airport", "Frankfurt", "large_airport", 50.03, 8.57, 1, nil],
                [4, "EDFE", nil, "Frankfurt-Egelsbach Airfield", "Egelsbach", "small_airport", 49.96, 8.64, 0, nil],
                [5, "XXHP", nil, "Frankfurt Heliport", "Frankfurt", "heliport", 50.04, 8.58, 0, nil],
                [6, "EDKX", nil, "Remote Airfield", "Nowhere", "small_airport", 52.00, 10.00, 0, nil],
            ]
            for a in airports {
                try db.execute(sql: """
                    INSERT INTO airports (id, icao, iata, name, city, country_code, continent, type,
                      latitude, longitude, default_search, keywords)
                    VALUES (?, ?, ?, ?, ?, 'XX', 'EU', ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(a))
            }
            try db.execute(sql: "INSERT INTO airports_fts (airports_fts) VALUES ('rebuild')")
        }
        try queue.close()
        return url
    }
}
