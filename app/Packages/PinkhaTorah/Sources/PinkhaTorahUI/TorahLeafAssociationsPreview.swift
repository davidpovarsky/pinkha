import PinkhaTorahCore
import SwiftUI

public struct TorahLeafAssociationsPreview: View {
    private let target: TorahTarget
    private let refreshToken: Int
    private let onManage: () -> Void
    private let onOpenReference: ((TorahInspectorSelection) -> Void)?
    @State private var workspace: TorahWorkspace?
    @State private var associations: [TorahAssociation] = []

    public init(databasePath: String, target: TorahTarget, refreshToken: Int, onOpenReference: ((TorahInspectorSelection) -> Void)? = nil, onManage: @escaping () -> Void) {
        self.target = target
        self.refreshToken = refreshToken
        self.onManage = onManage
        self.onOpenReference = onOpenReference
        _workspace = State(initialValue: try? TorahWorkspace.application(databasePath: databasePath))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !associations.isEmpty {
                ForEach(associations.prefix(2)) { association in
                    Button(action: onManage) {
                        HStack(spacing: 7) {
                            Image(systemName: TorahKindAppearance.symbol(for: association.kind))
                                .foregroundStyle(TorahKindAppearance.color(for: association.kind))
                            Text(association.labelHe).lineLimit(1).truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if association.kind == .ref, let onOpenReference {
                            Button {
                                onOpenReference(.init(providerID: association.providerID, canonicalRef: association.canonicalKey))
                            } label: {
#if canImport(UIKit)
                                Label { Text(l("Open in Inspector")) } icon: { Image(uiImage: TorahKindAppearance.menuImage(for: .ref)) }
#else
                                Label(l("Open in Inspector"), systemImage: TorahKindAppearance.symbol(for: .ref))
#endif
                            }
                        }
                    }
                    .accessibilityLabel("\(kindName(association.kind)), \(association.labelHe)")
                    .accessibilityIdentifier("torahLeafPreviewRow.\(association.id)")
                }

                if associations.count > 2 {
                    Button(action: onManage) {
                        Text(String(format: l("+%lld more"), Int64(associations.count - 2)))
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("torahLeafPreviewMoreButton")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("torahLeafPreview")
        .task(id: reloadID) { await reload() }
    }

    private var reloadID: String { "\(target.id):\(refreshToken)" }

    private func reload() async {
        guard let workspace else { return }
        do { associations = try await workspace.associations(for: target) }
        catch is CancellationError {} catch { associations = [] }
    }

    private func kindName(_ kind: TorahAssociationKind) -> String {
        switch kind { case .ref: l("Source"); case .word: l("Word"); case .topic: l("Topic") }
    }
}
