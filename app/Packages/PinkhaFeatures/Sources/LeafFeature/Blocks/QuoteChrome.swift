import SwiftUI

/// Shared thin vertical rule decoration used by both editable Quote blocks
/// and read-only Torah source quote blocks.
public struct QuoteChrome<Content: View>: View {
    let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 3)
                .padding(.vertical, 6)
            content
                .padding(.leading, 14)
        }
        .padding(.vertical, 4)
    }
}
