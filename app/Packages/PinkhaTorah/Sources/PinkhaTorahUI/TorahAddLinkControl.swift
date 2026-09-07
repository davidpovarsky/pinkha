import PinkhaTorahCore
import SwiftUI

public struct TorahAddLinkControl: View {
    private let onSelect: (TorahAssociationKind) -> Void

    public init(onSelect: @escaping (TorahAssociationKind) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            choice(.ref, title: l("Source"))
            choice(.word, title: l("Word"))
            choice(.topic, title: l("Topic"))
        } label: {
            Label(l("Add Torah link"), systemImage: "books.vertical")
        }
        .accessibilityIdentifier("torahAddLinkButton")
    }

    private func choice(_ kind: TorahAssociationKind, title: String) -> some View {
        Button {
            Task { @MainActor in
                await Task.yield()
                onSelect(kind)
            }
        } label: {
#if canImport(UIKit)
            Label { Text(title) } icon: { Image(uiImage: TorahKindAppearance.menuImage(for: kind)) }
#else
            Label(title, systemImage: TorahKindAppearance.symbol(for: kind))
#endif
        }
        .accessibilityIdentifier("torahAssociationKind\(kind.rawValue.capitalized)")
    }
}
