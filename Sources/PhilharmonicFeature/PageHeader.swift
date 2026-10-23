import SwiftUI

/// The top of a Philharmonic page that is not a group (Dashboard, Workforce): its name, large, and a line of
/// context on the right. The shell draws no navigation title, so the page names itself.
struct PageHeader<Trailing: View>: View {
    let title: Text
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(.largeTitle.bold())
                .foregroundStyle(Color.primary)
            Spacer(minLength: 12)
            trailing
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .textCase(nil)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
