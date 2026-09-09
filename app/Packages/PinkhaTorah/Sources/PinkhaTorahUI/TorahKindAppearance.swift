import PinkhaTorahCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum TorahKindAppearance {
    public static func symbol(for kind: TorahAssociationKind) -> String {
        switch kind { case .ref: "book.closed"; case .word: "textformat"; case .topic: "tag" }
    }

    public static func color(for kind: TorahAssociationKind) -> Color {
        switch kind { case .ref: .blue; case .word: .orange; case .topic: .purple }
    }

#if canImport(UIKit)
    public static func menuImage(for kind: TorahAssociationKind) -> UIImage {
        let color: UIColor = switch kind { case .ref: .systemBlue; case .word: .systemOrange; case .topic: .systemPurple }
        return UIImage(systemName: symbol(for: kind))!.withTintColor(color, renderingMode: .alwaysOriginal)
    }
#endif
}
