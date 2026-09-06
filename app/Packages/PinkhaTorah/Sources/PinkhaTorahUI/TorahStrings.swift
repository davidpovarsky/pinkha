import Foundation

public enum TorahStrings {
    public static var links: String { text("Torah links") }
    public static var storageUnavailable: String { text("Torah storage is unavailable.") }

    private static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
