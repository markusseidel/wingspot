package site.wingspot.core

/** What a profile image looks like and where it lives. */
object AvatarImage {
    /** Width and height in pixels of the image the phone uploads. */
    const val SIDE = 512

    /** The bucket refuses larger files. */
    const val MAX_BYTES = 512 * 1024

    /** How long others may keep a copy before asking again, in seconds. */
    const val CACHE_SECONDS = 300

    /** A square cut out of a picture: its left and top edge and its side, in pixels. */
    data class Square(val left: Int, val top: Int, val side: Int)

    /** The centred square to cut out of a picture of this size. */
    fun squareCrop(width: Int, height: Int): Square {
        val side = minOf(width, height)
        return Square((width - side) / 2, (height - side) / 2, side)
    }

    /** The folder name of a person. The storage rules compare it with the lowercase text of the user ID. */
    fun folder(userId: String): String = userId.lowercase()

    /** The public address of a person's image. It is the same for everyone, so lists need no extra data. */
    fun url(projectUrl: String, userId: String): String = projectUrl.trimEnd('/') + "/storage/v1/object/public/avatars/" + folder(userId) + "/avatar.jpg"
}
