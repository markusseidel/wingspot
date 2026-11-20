import Account
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Your invite code, following by code, the people you may know, and a link that was opened.
@MainActor
@Observable
final class InviteStore {
    private let backend: any InviteBackend

    /// Whose invite link was opened and is waiting for a "Follow?".
    var pendingOwner: InvitePerson?
    private var pendingCode: String?

    init(backend: any InviteBackend) {
        self.backend = backend
    }

    func code() async -> String? { try? await backend.myInviteCode() }
    func resetCode() async -> String? { try? await backend.resetInviteCode() }
    func suggestions() async -> [PersonSuggestion] { (try? await backend.suggestions()) ?? [] }
    func allowsSuggestions(of me: UUID) async -> Bool { (try? await backend.allowsSuggestions(of: me)) ?? true }

    func setAllowsSuggestions(_ allowed: Bool, as me: UUID) async -> Bool {
        (try? await backend.setAllowsSuggestions(allowed, as: me)) != nil
    }

    /// A link was opened: remember who it is for, and ask whether to follow them.
    func receive(code: String) async {
        pendingCode = code
        pendingOwner = try? await backend.inviteOwner(code: code)
    }

    /// Follows the owner of a code. `nil` if the code is unknown.
    func follow(code: String) async -> InvitePerson? {
        try? await backend.followByCode(code)
    }

    func followPending() async -> InvitePerson? {
        guard let code = pendingCode else { return nil }
        defer { pendingCode = nil; pendingOwner = nil }
        return await follow(code: code)
    }

    func dismissPending() {
        pendingCode = nil
        pendingOwner = nil
    }
}

/// Asks "Follow Anna?" when an invite link was opened.
struct InviteLinkAlert: ViewModifier {
    @Environment(InviteStore.self) private var invites
    @Environment(AccountStore.self) private var account

    func body(content: Content) -> some View {
        content.alert(
            Text("Follow \(invites.pendingOwner?.name ?? "")?"),
            isPresented: Binding(get: { invites.pendingOwner != nil && account.userID != nil }, set: { if !$0 { invites.dismissPending() } })
        ) {
            Button("Follow") { Task { _ = await invites.followPending() } }
            Button("Not now", role: .cancel) { invites.dismissPending() }
        } message: {
            Text("They invited you to Wingspot. You can unfollow any time.")
        }
    }
}

/// Invite friends: share your code, link and QR code, add someone by their code, and follow people you may know.
struct InviteView: View {
    @Environment(InviteStore.self) private var invites
    @Environment(SocialStore.self) private var social
    @Environment(AccountStore.self) private var account
    @State private var code: String?
    @State private var typed = ""
    @State private var message: LocalizedStringKey?
    @State private var suggestions: [PersonSuggestion] = []
    @State private var followed: Set<UUID> = []
    @State private var allowSuggestions = true
    @State private var allowLoaded = false
    @State private var confirmReset = false

    private var shareText: String {
        guard let code, let link = InviteLink.url(for: code) else { return "" }
        return String(localized: "Join me on Wingspot! My invite code is \(code), or open \(link.absoluteString)")
    }

    var body: some View {
        List {
            Section {
                if let code {
                    HStack {
                        Text(verbatim: code).font(.title2.monospaced().bold())
                        Spacer()
                        ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                    if let link = InviteLink.url(for: code), let image = QRCode.image(for: link.absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("QR code of your invite link")
                    }
                } else {
                    ProgressView()
                }
            } header: {
                Text("Your invite code")
            } footer: {
                Text("A friend who opens the link, scans the code or types it can follow you in one step.")
            }
            Section {
                HStack {
                    TextField("Code from a friend", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Follow") { Task { await addByCode() } }
                        .disabled(InviteLink.clean(typed) == nil)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Add a friend by code")
            }
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { person in
                        HStack(spacing: 12) {
                            AvatarView(id: person.userID, name: person.name, size: 36)
                            VStack(alignment: .leading) {
                                Text(verbatim: person.name)
                                Text(reasonText(person)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if followed.contains(person.userID) {
                                Text("Following").font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Button("Follow") { Task { await follow(person) } }.buttonStyle(.bordered)
                            }
                        }
                    }
                } header: {
                    Text("People you may know")
                }
            }
            Section {
                if allowLoaded {
                    Toggle("Suggest me to others", isOn: Binding(get: { allowSuggestions }, set: { changeSuggestions($0) }))
                }
                Button("Make a new code", role: .destructive) { confirmReset = true }
            } footer: {
                Text("A new code ends the old link and code.")
            }
        }
        .navigationTitle("Invite friends")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Make a new invite code?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Make a new code", role: .destructive) { Task { code = await invites.resetCode() ?? code } }
        } message: {
            Text("The old link and code stop working.")
        }
        .task {
            code = await invites.code()
            suggestions = await invites.suggestions()
            if let me = account.userID {
                allowSuggestions = await invites.allowsSuggestions(of: me)
                allowLoaded = true
            }
        }
    }

    private func reasonText(_ person: PersonSuggestion) -> LocalizedStringKey {
        person.reason == "tagged" ? "Was on a flight with you" : "Followed by \(person.mutual) people you follow"
    }

    private func addByCode() async {
        guard let clean = InviteLink.clean(typed) else { return }
        if let person = await invites.follow(code: clean) {
            message = "You now follow \(person.name)."
            typed = ""
        } else {
            message = "That code doesn't match anyone."
        }
    }

    private func follow(_ person: PersonSuggestion) async {
        followed.insert(person.userID)
        do { try await social.follow(person.userID) } catch { followed.remove(person.userID) }
    }

    private func changeSuggestions(_ on: Bool) {
        guard let me = account.userID else { return }
        allowSuggestions = on
        Task { if await !invites.setAllowsSuggestions(on, as: me) { allowSuggestions = !on } }
    }
}

/// A QR code of some text, drawn crisp.
enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
