import Foundation
import Testing
@testable import Account

@Suite struct CompareTests {
    @Test func theAnswerOfTheServerIsRead() throws {
        let json = """
        {"me":{"flights":2,"distance_km":1200,"airports":3,"countries":3,"airlines":1,"types":2},
         "them":{"flights":2,"distance_km":1400,"airports":3,"countries":3,"airlines":2,"types":1},
         "airports":{"common":[{"key":1,"code":"ZA1","name":"Alpha"}],"mine":[],"theirs":[{"key":4,"code":"ZA4","name":"Delta"}]},
         "countries":{"common":[{"key":"DE","code":"DE"}],"mine":[],"theirs":[]},
         "airlines":{"common":[],"mine":[],"theirs":[]},
         "types":{"common":[],"mine":[{"key":"ZT2","code":"ZT2","name":"Test Two"}],"theirs":[]}}
        """
        let result = try CompareResult.decode(Data(json.utf8))
        #expect(result.me.distanceKm == 1200)
        #expect(result.them.airlines == 2)
        #expect(result.airports.theirs.first?.name == "Delta")
        #expect(result.countries.common.first?.code == "DE")
        #expect(result.countries.common.first?.name == nil)
        #expect(result.types.mine.count == 1)
    }
}
