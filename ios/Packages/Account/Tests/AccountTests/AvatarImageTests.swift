import Foundation
import Testing
@testable import Account

@Suite("Profile image")
struct AvatarImageTests {
    @Test("a wide picture is cut to a centred square")
    func wide() {
        #expect(AvatarImage.squareCrop(width: 4000, height: 3000) == CGRect(x: 500, y: 0, width: 3000, height: 3000))
    }

    @Test("a tall picture is cut to a centred square")
    func tall() {
        #expect(AvatarImage.squareCrop(width: 3000, height: 4000) == CGRect(x: 0, y: 500, width: 3000, height: 3000))
    }

    @Test("a square picture stays whole")
    func square() {
        #expect(AvatarImage.squareCrop(width: 800, height: 800) == CGRect(x: 0, y: 0, width: 800, height: 800))
    }

    @Test("the address has the user folder in lowercase, as the storage rules compare it")
    func address() {
        let id = UUID(uuidString: "4B9CB879-7298-4EFB-A82D-E0BF893E4448")!
        let url = AvatarImage.url(projectURL: URL(string: "https://example.supabase.co")!, userID: id)
        #expect(url.absoluteString == "https://example.supabase.co/storage/v1/object/public/avatars/4b9cb879-7298-4efb-a82d-e0bf893e4448/avatar.jpg")
    }
}
