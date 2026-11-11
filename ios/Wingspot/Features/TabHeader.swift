import SwiftUI

/// The large title at the top of a tab, drawn right under the status bar so all four tabs look the same.
/// The navigation bar is hidden on these screens. Screens that are pushed on top still get their own bar.
struct TabHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing.font(.title3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

extension TabHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
}

extension View {
    /// Puts the tab's large title above this view and hides the navigation bar.
    func tabHeader<Trailing: View>(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            TabHeader(title: title, trailing: trailing)
            self.frame(maxHeight: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    func tabHeader(_ title: LocalizedStringKey) -> some View {
        tabHeader(title) { EmptyView() }
    }
}
