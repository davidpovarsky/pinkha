import SwiftUI
import PinkhaTorahCore
import PinkhaTorahUI
import PinkhaDesignSystem

public struct TorahSourceQuoteRowView: View {
    public let association: TorahAssociation
    public let text: String
    public let onOpen: (TorahInspectorSelection) -> Void
    
    @ScaledMetric private var spacingS: CGFloat = 8
    @ScaledMetric private var spacingXS: CGFloat = 4

    public init(association: TorahAssociation, text: String, onOpen: @escaping (TorahInspectorSelection) -> Void) {
        self.association = association
        self.text = text
        self.onOpen = onOpen
    }
    
    public var body: some View {
        QuoteChrome {
            VStack(alignment: .leading, spacing: spacingS) {
                HStack(alignment: .center, spacing: spacingXS) {
                    Image(systemName: "book.closed")
                        .foregroundStyle(Color.pinkhaLabelSecondary)
                        .font(.caption2)
                    
                    Text(association.labelHe)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.pinkhaLabelSecondary)
                    
                    Spacer()
                    
                    Button {
                        onOpen(.init(
                            providerID: association.providerID,
                            canonicalRef: association.canonicalKey,
                            preferredSegmentRef: association.canonicalKey
                        ))
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(Color.pinkhaLabelTertiary)
                            .padding(spacingXS)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open in Inspector")
                }
                .environment(\.layoutDirection, .rightToLeft)
                
                Text(text)
                    .font(.body)
                    .foregroundStyle(Color.pinkhaLabel)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }
}
