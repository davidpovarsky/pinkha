import Foundation
import PinkhaTorahCore

public enum TorahStrings {
    public static var links: String { text("Torah links") }
    public static var storageUnavailable: String { text("Torah storage is unavailable.") }
    public static func message(for error: Error) -> String {
        guard let torah = error as? TorahError else { return error.localizedDescription }
        switch torah {
        case .invalidReference: return text("The reference is not valid.")
        case .referenceTooBroad: return text("Choose a more specific source.")
        case .noText: return text("No text is available for this source.")
        default: return error.localizedDescription
        }
    }

    private static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
