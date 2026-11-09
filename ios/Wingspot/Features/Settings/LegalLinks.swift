import SwiftUI

/// Where the legal pages and the contact address live. The pages are published on wingspot.site.
enum LegalLinks {
    static let privacy = URL(string: "https://wingspot.site/privacy")!
    static let terms = URL(string: "https://wingspot.site/terms")!
    static let imprint = URL(string: "https://wingspot.site/imprint")!
    static let contactAddress = "support@wingspot.site"
    static var contact: URL { URL(string: "mailto:\(contactAddress)")! }
}

/// Privacy policy, terms, imprint and contact, for Settings and the sign-in screen.
struct LegalLinksSection: View {
    var compact = false

    var body: some View {
        Section {
            Link("Privacy policy", destination: LegalLinks.privacy)
            Link("Terms of use", destination: LegalLinks.terms)
            if !compact {
                Link("Imprint", destination: LegalLinks.imprint)
                Link(destination: LegalLinks.contact) {
                    LabeledContent("Contact") { Text(verbatim: LegalLinks.contactAddress) }
                }
            }
        } header: {
            if !compact { Text("About") }
        } footer: {
            if compact { Text("By signing in you accept the terms of use and the privacy policy.") }
        }
    }
}
