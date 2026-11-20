package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals

class AvatarTests {
    @Test fun aWidePictureIsCutToACentredSquare() {
        assertEquals(AvatarImage.Square(500, 0, 3000), AvatarImage.squareCrop(4000, 3000))
    }

    @Test fun aTallPictureIsCutToACentredSquare() {
        assertEquals(AvatarImage.Square(0, 500, 3000), AvatarImage.squareCrop(3000, 4000))
    }

    @Test fun aSquarePictureStaysWhole() {
        assertEquals(AvatarImage.Square(0, 0, 800), AvatarImage.squareCrop(800, 800))
    }

    @Test fun theAddressHasTheUserFolderInLowercase() {
        assertEquals(
            "https://example.supabase.co/storage/v1/object/public/avatars/4b9cb879-7298-4efb-a82d-e0bf893e4448/avatar.jpg",
            AvatarImage.url("https://example.supabase.co/", "4B9CB879-7298-4EFB-A82D-E0BF893E4448"),
        )
    }
}
