import Account
import SwiftUI

/// What a share card says. It is generic on purpose: a flight, a badge and a level are all a small line, a big line and a number.
struct ShareCardModel: Equatable {
    /// A short label on top, like FLOWN or BADGE.
    let kicker: String
    /// The big line: a route, a badge name or a level.
    let headline: String
    /// A number or a short second line under it.
    let figure: String?
    /// A small line with the details.
    let caption: String?
    /// Who is sharing.
    let name: String
    /// The text sent along with the picture.
    let message: String
}

/// The picture that is shared: portrait, dark, with the brand colour.
struct ShareCardView: View {
    let model: ShareCardModel
    let code: String?

    private let orange = Color(red: 1.0, green: 0.42, blue: 0.10)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.09, blue: 0.20), Color(red: 0.08, green: 0.14, blue: 0.30)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "scope").font(.title2.bold()).foregroundStyle(orange)
                    Text(verbatim: "Wingspotted").font(.title3.weight(.heavy)).foregroundStyle(.white)
                    Spacer()
                    Text(verbatim: model.kicker.uppercased())
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(orange, in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(verbatim: model.headline)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(3)
                    .foregroundStyle(.white)
                if let figure = model.figure {
                    Text(verbatim: figure)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(orange)
                        .padding(.top, 6)
                }
                if let caption = model.caption {
                    Text(verbatim: caption).font(.callout).foregroundStyle(.white.opacity(0.75)).padding(.top, 10)
                }
                Spacer()
                Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
                HStack {
                    Text(verbatim: model.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    if let code { Text(verbatim: code).font(.subheadline.monospaced()).foregroundStyle(.white.opacity(0.75)) }
                }
                .padding(.top, 12)
            }
            .padding(28)
        }
        .frame(width: 360, height: 450)
    }
}

/// A Share button that draws the card as a picture and opens the system share sheet.
struct ShareCardButton: View {
    let model: ShareCardModel
    @Environment(InviteStore.self) private var invites
    @State private var image: Image?
    @State private var code: String?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, message: Text(verbatim: message), preview: SharePreview(model.headline, image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Share", systemImage: "square.and.arrow.up").foregroundStyle(.secondary)
            }
        }
        .task(id: model) {
            code = await invites.code()
            let renderer = ImageRenderer(content: ShareCardView(model: model, code: code))
            renderer.scale = 3
            if let ui = renderer.uiImage { image = Image(uiImage: ui) }
        }
    }

    private var message: String {
        guard let code, let link = InviteLink.url(for: code) else { return model.message }
        return model.message + " " + String(localized: "Join me on Wingspotted! My invite code is \(code), or open \(link.absoluteString)")
    }
}
