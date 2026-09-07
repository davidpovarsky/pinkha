import Foundation
import PinkhaTorahCore

public enum TorahStrings {
    public static var links: String { text("Torah links") }
    public static var storageUnavailable: String { text("Torah storage is unavailable.") }
    public static var source: String { text("Source") }
    public static var close: String { text("Close") }
    public static var insertIntoDocument: String { text("Insert into document") }
    public static var copy: String { text("Copy") }
    public static var viewDetails: String { text("View details") }
    public static var couldNotLoadSource: String { text("Could not load source") }
    public static var couldNotLoadRelatedSources: String { text("Could not load related sources") }
    public static var couldNotInsertSource: String { text("Could not insert source") }
    public static var retry: String { text("Retry") }

    public static func message(for error: Error) -> String {
        guard let torah = error as? TorahError else { return text("Could not load source") }
        switch torah {
        case .invalidReference: return text("The reference is not valid.")
        case .referenceTooBroad: return text("Choose a more specific source.")
        case .noText: return text("No text is available for this source.")
        case .missingProvider: return text("No Torah provider is available.")
        case .noResults: return text("No results")
        case .malformedResponse, .network: return text("Could not load source")
        case .storage: return text("Torah storage is unavailable.")
        }
    }

    public static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
