import Foundation

extension UUID {
    /// A time-ordered UUID (RFC 9562), created on the device so that retrying a check-in can't create a duplicate.
    public static func v7(at date: Date = Date()) -> UUID {
        let milliseconds = UInt64(max(0, date.timeIntervalSince1970) * 1000)
        var bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: milliseconds >> UInt64((5 - index) * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }
}
