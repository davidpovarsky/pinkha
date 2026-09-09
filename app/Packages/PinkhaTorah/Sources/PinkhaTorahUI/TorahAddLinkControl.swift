import PinkhaTorahCore
import SwiftUI

public struct TorahAddLinkControl: View {
    private let onSelect: (TorahAssociationKind) -> Void
    @State private var chooserPresented = false
    @State private var pendingKind: TorahAssociationKind?

    public init(onSelect: @escaping (TorahAssociationKind) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        Button { chooserPresented = true } label: {
            Label(l("Add Torah link"), systemImage: "books.vertical")
        }
        .accessibilityIdentifier("torahAddLinkButton")
        .popover(
            isPresented: $chooserPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            List {
                choice(.ref, title: l("Source"))
                choice(.word, title: l("Word"))
                choice(.topic, title: l("Topic"))
            }
            .listStyle(.plain)
            .frame(minWidth: 240, idealWidth: 280, minHeight: 150, idealHeight: 168)
            .onDisappear { completePendingSelection() }
        }
    }

    private func choice(_ kind: TorahAssociationKind, title: String) -> some View {
        Button {
            pendingKind = kind
            chooserPresented = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: TorahKindAppearance.symbol(for: kind))
                    .foregroundStyle(TorahKindAppearance.color(for: kind))
                Text(title).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("torahAssociationKind\(kind.rawValue.capitalized)")
    }

    private func completePendingSelection() {
        guard let kind = pendingKind else { return }
        pendingKind = nil
        onSelect(kind)
    }
}
