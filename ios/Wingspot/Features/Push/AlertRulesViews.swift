import Account
import SwiftUI

extension AlertRule.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .spotted: "Spotted"
        case .flown: "Flown"
        case .airport: "Airport visits"
        }
    }
}

/// On a profile you follow: which of this person's new check-ins send you a notification.
struct PersonAlertsSection: View {
    let person: Person
    @Environment(PushStore.self) private var push

    var body: some View {
        Section {
            if push.authorization == .denied {
                Text("Notifications are off for Wingspot in the system settings.").foregroundStyle(.secondary)
                Button("Open system settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } else {
                ForEach(AlertRule.Kind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: binding(kind))
                }
            }
        } header: {
            Text("Notify me")
        } footer: {
            if push.prefs?.followedCheckins == false {
                Text("Alerts for people you follow are switched off in Settings.")
            } else {
                Text("You get a notification when this person checks in, for the check-ins you can see. They are not told.")
            }
        }
        .task {
            await push.sync()
            await push.loadAlertRules()
            if push.prefs == nil { await push.loadPrefs() }
        }
    }

    private func binding(_ kind: AlertRule.Kind) -> Binding<Bool> {
        Binding(
            get: { push.alertRule(for: person.id).isOn(kind) },
            set: { on in
                Task {
                    // The first alert is a good moment to ask for permission.
                    if on, push.authorization != .allowed {
                        guard await push.enable() else { return }
                    }
                    await push.setAlert(kind, on: on, for: person.id)
                }
            }
        )
    }
}

/// Settings: everyone you get alerts from, with a way to stop each.
struct AlertRulesView: View {
    @Environment(PushStore.self) private var push

    private var rules: [AlertRule] {
        push.alertRules.values.sorted { ($0.username ?? "") < ($1.username ?? "") }
    }

    var body: some View {
        List {
            if rules.isEmpty {
                Text("No alerts yet. Open the profile of someone you follow to set one.").foregroundStyle(.secondary)
            }
            ForEach(rules) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: rule.displayName ?? rule.username ?? "?")
                    Text(verbatim: summary(rule)).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .swipeActions {
                    Button("Stop", role: .destructive) {
                        Task { for kind in AlertRule.Kind.allCases { await push.setAlert(kind, on: false, for: rule.target) } }
                    }
                }
            }
        }
        .navigationTitle("People you get alerts from")
        .navigationBarTitleDisplayMode(.inline)
        .task { await push.loadAlertRules() }
        .refreshable { await push.loadAlertRules() }
    }

    private func summary(_ rule: AlertRule) -> String {
        let names: [(AlertRule.Kind, LocalizedStringResource)] = [
            (.spotted, "Spotted"), (.flown, "Flown"), (.airport, "Airport visits"),
        ]
        return names.filter { rule.isOn($0.0) }.map { String(localized: $0.1) }.joined(separator: ", ")
    }
}
