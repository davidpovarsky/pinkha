import PinkhaTorahCore
import SwiftUI

public struct TorahAddLinkControl: View {
    private let onSelect: (TorahAssociationKind) -> Void
    @State private var isPresented = false

    public init(onSelect: @escaping (TorahAssociationKind) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(l("Add Torah link"), systemImage: "books.vertical")
        }
        .accessibilityIdentifier("torahAddLinkButton")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 4) {
                choice(.ref, title: l("Source"), icon: "book.closed")
                choice(.word, title: l("Word"), icon: "textformat")
                choice(.topic, title: l("Topic"), icon: "tag")
            }
            .padding(12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("torahAddKindPopover")
        }
    }

    private func choice(_ kind: TorahAssociationKind, title: String, icon: String) -> some View {
        Button {
            isPresented = false
            Task { @MainActor in
                await Task.yield()
                onSelect(kind)
            }
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("torahAssociationKind\(kind.rawValue.capitalized)")
    }
}
