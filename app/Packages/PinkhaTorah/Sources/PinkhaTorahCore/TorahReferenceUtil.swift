import Foundation

/// Utility functions for parsing and manipulating Torah references and canonical keys.
public enum TorahReferenceUtil {
    /// Extracts the book/work title from a canonical reference.
    ///
    /// Examples:
    /// - `"Genesis 1:1"` -> `"Genesis"`
    /// - `"Rosh Hashanah 16b"` -> `"Rosh Hashanah"`
    /// - `"I Kings 3:1"` -> `"I Kings"`
    /// - `"Song of Songs 1:1"` -> `"Song of Songs"`
    /// - `"Genesis"` -> `"Genesis"`
    public static func bookTitle(from reference: String) -> String {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(" ") else { return trimmed }

        let parts = trimmed.split(separator: " ")
        guard parts.count > 1 else { return trimmed }

        var bookParts: [Substring] = []
        for (idx, part) in parts.enumerated() {
            // Roman numeral prefixes (e.g. "I Samuel", "II Kings") are part of the book title
            let isRomanPrefix = (idx == 0) && ["I", "II", "III", "IV"].contains(part)
            if !isRomanPrefix, let firstChar = part.first, firstChar.isNumber {
                break
            }
            bookParts.append(part)
        }

        if bookParts.isEmpty {
            return trimmed
        }
        return bookParts.joined(separator: " ")
    }

    /// Extracts the section reference (chapter, daf/page) from a segment or section reference.
    ///
    /// In Sefaria, sections are chapters or pages (e.g. `"Genesis 1"`, `"Berakhot 2a"`),
    /// while segments are verses or sub-segments (e.g. `"Genesis 1:5"`, `"Berakhot 2a:1"`).
    ///
    /// Examples:
    /// - `"Genesis 1:5"` -> `"Genesis 1"`
    /// - `"Berakhot 2a:1"` -> `"Berakhot 2a"`
    /// - `"Genesis 1"` -> `"Genesis 1"`
    /// - `"Rosh Hashanah 16b"` -> `"Rosh Hashanah 16b"`
    public static func sectionRef(from reference: String) -> String {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastColon = trimmed.lastIndex(of: ":") else {
            return trimmed
        }
        let beforeColon = String(trimmed[..<lastColon])
        return beforeColon.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns whether the given reference represents a segment (contains a colon separator).
    public static func isSegmentRef(_ reference: String) -> Bool {
        reference.contains(":")
    }
}
