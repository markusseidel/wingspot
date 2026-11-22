package site.wingspot.core

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

/**
 * The tracks of imported flights, kept **on this phone only**: one small file per check-in, named by its id. Nothing here is
 * uploaded. A file is 4 bytes of header ("WTR1") and then 16 bytes per position, longitude and latitude as little-endian
 * 64-bit floats, so 50 000 positions take about 800 kB. The iPhone app uses the same layout.
 */
class FlightTrackFiles(private val directory: File) {
    private fun file(id: UUID) = File(directory, "${id.toString().lowercase()}.trk")

    fun save(points: List<GeoCoordinate>, id: UUID) {
        directory.mkdirs()
        val buffer = ByteBuffer.allocate(HEADER.size + points.size * 16).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put(HEADER)
        for (point in points) {
            buffer.putDouble(point.longitude)
            buffer.putDouble(point.latitude)
        }
        // Written beside the file and moved over it, so a crash never leaves half a track.
        val target = file(id)
        val temporary = File(directory, "${target.name}.tmp")
        temporary.writeBytes(buffer.array())
        if (!temporary.renameTo(target)) { target.delete(); check(temporary.renameTo(target)) { "could not save the track" } }
    }

    /** The positions saved for a check-in, or null if there are none or the file is damaged. */
    fun load(id: UUID): List<GeoCoordinate>? {
        val source = file(id)
        if (!source.isFile) return null
        val data = source.readBytes()
        if (data.size < HEADER.size || !data.copyOfRange(0, HEADER.size).contentEquals(HEADER) || (data.size - HEADER.size) % 16 != 0) return null
        val buffer = ByteBuffer.wrap(data, HEADER.size, data.size - HEADER.size).order(ByteOrder.LITTLE_ENDIAN)
        val points = ArrayList<GeoCoordinate>((data.size - HEADER.size) / 16)
        while (buffer.remaining() >= 16) {
            val longitude = buffer.getDouble()
            val latitude = buffer.getDouble()
            points.add(GeoCoordinate(latitude, longitude))
        }
        return points
    }

    fun has(id: UUID): Boolean = file(id).isFile

    fun delete(id: UUID) {
        file(id).delete()
    }

    fun deleteAll() {
        directory.listFiles()?.forEach { if (it.name.endsWith(".trk") || it.name.endsWith(".tmp")) it.delete() }
    }

    private companion object {
        val HEADER = "WTR1".toByteArray(Charsets.US_ASCII)
    }
}
