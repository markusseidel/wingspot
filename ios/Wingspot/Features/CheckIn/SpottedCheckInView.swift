import SwiftUI
import WingspotCore

/// First cut of the Spotted check-in: registration entry with live normalization.
/// Saving arrives in Phase 1 together with local persistence.
struct SpottedCheckInView: View {
    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var registration: Registration? { Registration(input) }

    var body: some View {
        Form {
            Section {
                TextField("Registration, e.g. DAIMA", text: $input)
                    .font(.system(.title2, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isFocused)
            } footer: {
                status
            }

            Section {
                Button("Check in") {}
                    .disabled(true)
            } footer: {
                Text("Saving check-ins comes in Phase 1.")
            }
        }
        .navigationTitle("Spotted")
        .onAppear { isFocused = true }
    }

    @ViewBuilder private var status: some View {
        if let registration {
            Label {
                Text(registration.value).font(.system(.body, design: .monospaced).bold())
                    + Text("  ·  \(Self.countryName(registration.countryCode))")
            } icon: {
                Text(Self.flag(registration.countryCode))
            }
            .accessibilityLabel("\(registration.value), registered in \(Self.countryName(registration.countryCode))")
        } else if !input.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Not a valid registration yet")
        }
    }

    private static func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private static func flag(_ code: String) -> String {
        code.unicodeScalars
            .compactMap { Unicode.Scalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

#Preview {
    NavigationStack { SpottedCheckInView() }
}
