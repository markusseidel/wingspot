import Testing
@testable import Account

struct NonceTests {
    @Test func theHashMatchesAKnownVector() {
        #expect(Nonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Nonce.sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func randomValuesHaveTheRightLengthAndCharacters() {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-.")
        for length in [16, 32, 64] {
            let value = Nonce.random(length: length)
            #expect(value.count == length)
            #expect(value.allSatisfy(allowed.contains))
        }
    }

    @Test func randomValuesDiffer() {
        let values = Set((0..<50).map { _ in Nonce.random() })
        #expect(values.count == 50)
    }
}
