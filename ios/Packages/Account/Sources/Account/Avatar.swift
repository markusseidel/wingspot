import CoreGraphics
import Foundation
import Supabase

/// Setting and removing the signed-in person's profile image.
public protocol AvatarBackend: Sendable {
    /// Replaces the image with this JPEG: a square, at most `AvatarImage.maxBytes`.
    func uploadAvatar(_ jpeg: Data) async throws
    func removeAvatar() async throws
}

/// What a profile image looks like and where it lives.
public enum AvatarImage {
    /// Width and height in pixels of the image the phone uploads.
    public static let side = 512
    /// The bucket refuses larger files.
    public static let maxBytes = 512 * 1024
    /// How long others may keep a copy before asking again, in seconds.
    static let cacheSeconds = 300

    /// The centred square to cut out of a picture of this size.
    public static func squareCrop(width: CGFloat, height: CGFloat) -> CGRect {
        let edge = min(width, height)
        return CGRect(x: (width - edge) / 2, y: (height - edge) / 2, width: edge, height: edge)
    }

    /// The folder name of a person. The storage rules compare it with the lowercase text of the user ID.
    static func folder(_ userID: UUID) -> String { userID.uuidString.lowercased() }

    /// The public address of a person's image. It is the same for everyone, so lists need no extra data.
    public static func url(projectURL: URL, userID: UUID) -> URL {
        projectURL.appending(path: "storage/v1/object/public/avatars/\(folder(userID))/avatar.jpg")
    }
}

extension SupabaseAccountBackend: AvatarBackend {
    public func uploadAvatar(_ jpeg: Data) async throws {
        try await avatarRequest { client, id in
            try await client.storage.from("avatars").upload(
                "\(AvatarImage.folder(id))/avatar.jpg", data: jpeg,
                options: FileOptions(cacheControl: "\(AvatarImage.cacheSeconds)", contentType: "image/jpeg", upsert: true)
            )
            // The version in the address is for the profile row. Lists use the plain address.
            let address = AvatarImage.url(projectURL: projectURL, userID: id).absoluteString + "?v=\(Int(Date().timeIntervalSince1970))"
            try await Self.saveAvatarAddress(address, id: id, client: client)
        }
    }

    public func removeAvatar() async throws {
        try await avatarRequest { client, id in
            _ = try await client.storage.from("avatars").remove(paths: ["\(AvatarImage.folder(id))/avatar.jpg"])
            try await Self.saveAvatarAddress(nil, id: id, client: client)
        }
    }

    private static func saveAvatarAddress(_ address: String?, id: UUID, client: SupabaseClient) async throws {
        _ = try await client.from("profiles")
            .update(AvatarUpdate(avatarURL: address), returning: .minimal)
            .eq("id", value: id)
            .execute()
    }
}

private struct AvatarUpdate: Encodable {
    let avatarURL: String?

    private enum CodingKeys: String, CodingKey { case avatarURL = "avatar_url" }

    // An explicit null clears the column. The synthesized version would leave the key out.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(avatarURL, forKey: .avatarURL)
    }
}

extension UnconfiguredAccountBackend: AvatarBackend {
    public func uploadAvatar(_ jpeg: Data) async throws { throw AccountError.notConfigured }
    public func removeAvatar() async throws { throw AccountError.notConfigured }
}

/// Someone's level and earned badges for their profile page, as the server sends them (`get_person_progress`).
public protocol PersonProgressBackend: Sendable {
    /// The JSON of the answer, or `nil` when the profile can't be seen: private, or blocked.
    func personProgress(_ id: UUID) async throws -> Data?
}

extension SupabaseAccountBackend: PersonProgressBackend {
    public func personProgress(_ id: UUID) async throws -> Data? {
        let data = try await mappingErrors { try await client.rpc("get_person_progress", params: ["target": id]).execute().data }
        // A profile that can't be seen answers with a JSON null.
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" ? nil : data
    }
}

extension UnconfiguredAccountBackend: PersonProgressBackend {
    public func personProgress(_ id: UUID) async throws -> Data? { throw AccountError.notConfigured }
}
