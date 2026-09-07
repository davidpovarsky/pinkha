import UIKit
import PinkhaFFI

public let pinkhaParagraphSeparator = "\u{2029}"
public let pinkhaLineSeparator = "\u{2028}"

/// Legacy LF represented a visual line break. Normalize only in the editor's
/// attributed value; persistence is updated naturally on the next user save.
public func normalizedRichText(_ value: String) -> String {
    value.replacingOccurrences(of: "\r\n", with: pinkhaLineSeparator)
        .replacingOccurrences(of: "\r", with: pinkhaLineSeparator)
        .replacingOccurrences(of: "\n", with: pinkhaLineSeparator)
}

public func pinkhaParagraphStyle(
    for font: UIFont,
    indentLevel: UInt8 = 0,
    writingDirection: NSWritingDirection = .natural
) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.paragraphSpacing = font.lineHeight * 0.45
    let indent = CGFloat(indentLevel) * font.lineHeight * 1.3
    style.firstLineHeadIndent = indent
    style.headIndent = indent
    style.baseWritingDirection = writingDirection
    return style
}

public enum PinkhaParagraphIndent {
    public static let maximumLevel: UInt8 = 6

    /// Paragraph ranges use U+2029 (and legacy CR/LF) as boundaries. U+2028 is
    /// intentionally a soft line break and therefore never splits a paragraph.
    public static func ranges(in string: String, intersecting selection: NSRange) -> [NSRange] {
        let value = string as NSString
        let length = value.length
        let location = selection.location == NSNotFound ? length : min(selection.location, length)
        let end = min(location + selection.length, length)
        let normalized = NSRange(location: location, length: max(0, end - location))
        var all: [NSRange] = []
        var start = 0
        for index in 0..<length {
            let scalar = value.character(at: index)
            if scalar == 0x2029 || scalar == 0x000A || scalar == 0x000D {
                all.append(NSRange(location: start, length: index - start + 1))
                start = index + 1
            }
        }
        if start < length || all.isEmpty || start == length {
            all.append(NSRange(location: start, length: length - start))
        }
        if normalized.length == 0 {
            return [all.first(where: {
                ($0.length == 0 && $0.location == location)
                    || (location >= $0.location && location < NSMaxRange($0))
            }) ?? all.last!]
        }
        return all.filter { NSIntersectionRange($0, normalized).length > 0 }
    }

    public static func level(in attributed: NSAttributedString, range: NSRange) -> UInt8 {
        guard range.length > 0 else { return 0 }
        var level: UInt8 = 0
        attributed.enumerateAttribute(.pinkhaParagraphIndentLevel, in: range) { value, _, _ in
            if let number = value as? NSNumber {
                level = max(level, min(number.uint8Value, maximumLevel))
            }
        }
        return level
    }

    public static func canChange(
        by delta: Int,
        in attributed: NSAttributedString,
        selection: NSRange
    ) -> Bool {
        ranges(in: attributed.string, intersecting: selection).contains { range in
            let current = Int(level(in: attributed, range: range))
            return delta > 0 ? current < Int(maximumLevel) : current > 0
        }
    }

    @discardableResult
    public static func apply(
        delta: Int,
        to attributed: NSMutableAttributedString,
        selection: NSRange,
        font: UIFont,
        writingDirection: NSWritingDirection = .natural
    ) -> Bool {
        var changed = false
        for range in ranges(in: attributed.string, intersecting: selection) where range.length > 0 {
            let current = Int(level(in: attributed, range: range))
            let next = UInt8(max(0, min(Int(maximumLevel), current + delta)))
            guard Int(next) != current else { continue }
            changed = true
            if next == 0 {
                attributed.removeAttribute(.pinkhaParagraphIndentLevel, range: range)
            } else {
                attributed.addAttribute(.pinkhaParagraphIndentLevel, value: Int(next), range: range)
            }
            let existing = attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                as? NSParagraphStyle
            let style = (existing?.mutableCopy() as? NSMutableParagraphStyle)
                ?? (pinkhaParagraphStyle(for: font).mutableCopy() as! NSMutableParagraphStyle)
            let indent = CGFloat(next) * font.lineHeight * 1.3
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            style.baseWritingDirection = writingDirection
            attributed.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return changed
    }
}

// ── Conversion Span ↔ NSAttributedString ─────────────────────────────────────

/// Converts an array of `InlineTextFfi` spans into an `NSAttributedString` using `police` as the base font.
///
/// Default foreground precedence : inline `.color(...)` on the span
/// (set inside the loop) wins over `blockColor`, which wins over
/// `themeForeground`, which wins over the system `.label`. Inline
/// color is *not* persisted as `.pinkhaColor` on spans that only
/// inherit a higher tier, so removing the inline color naturally
/// falls back to whichever default applies at the next render.
public func spansToAttributed(
    _ spans: [InlineTextFfi],
    police: UIFont,
    blockColor: String? = nil,
    themeForeground: UIColor? = nil,
    writingDirection: NSWritingDirection = .natural
) -> NSAttributedString {
    guard !spans.isEmpty else { return NSAttributedString() }
    let defaultForeground: UIColor = blockColor.map(uiColorFromName)
        ?? themeForeground
        ?? .label
    let result = NSMutableAttributedString()
    for span in spans {
        var isBold   = false
        var isItalic = false
        var paragraphIndent: UInt8?
        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: defaultForeground]
        for style in span.styles {
            switch style {
            case .bold:              isBold = true
            case .italic:            isItalic = true
            case .underline:         attrs[.underlineStyle]      = NSUnderlineStyle.single.rawValue
            case .strikethrough:     attrs[.strikethroughStyle]  = NSUnderlineStyle.single.rawValue
            case .color(let nom):    attrs[.foregroundColor] = uiColorFromName(nom); attrs[.pinkhaColor] = nom
            case .link(let url):     if let u = URL(string: url) { attrs[.link] = u }
            case .paragraphIndent(let level): paragraphIndent = min(level, PinkhaParagraphIndent.maximumLevel)
            }
        }
        attrs[.font] = fontWithTraits(police, bold: isBold, italic: isItalic)
        attrs[.paragraphStyle] = pinkhaParagraphStyle(
            for: police, indentLevel: paragraphIndent ?? 0, writingDirection: writingDirection)
        if let paragraphIndent { attrs[.pinkhaParagraphIndentLevel] = Int(paragraphIndent) }
        if isBold   { attrs[.pinkhaBold]   = true }
        if isItalic {
            attrs[.pinkhaItalic] = true
            attrs[.pinkhaObliqueness] = 0.2
        }
        result.append(NSAttributedString(string: normalizedRichText(span.content), attributes: attrs))
    }
    // Paragraph indentation is paragraph-scoped even when the persisted style
    // arrived on only one inline run. Normalize it over each whole paragraph.
    let fullSelection = NSRange(location: 0, length: result.length)
    for range in PinkhaParagraphIndent.ranges(in: result.string, intersecting: fullSelection)
        where range.length > 0 {
        var explicitLevel: UInt8?
        result.enumerateAttribute(.pinkhaParagraphIndentLevel, in: range) { value, _, _ in
            if let number = value as? NSNumber {
                explicitLevel = max(explicitLevel ?? 0, min(number.uint8Value, PinkhaParagraphIndent.maximumLevel))
            }
        }
        guard let level = explicitLevel else { continue }
        result.addAttribute(.pinkhaParagraphIndentLevel, value: Int(level), range: range)
        result.addAttribute(.paragraphStyle, value: pinkhaParagraphStyle(
            for: police, indentLevel: level, writingDirection: writingDirection), range: range)
    }
    return result
}

/// Converts an `NSAttributedString` into an array of `InlineTextFfi` spans.
/// Detects bold/italic via custom keys (`.pinkhaBold`/`.pinkhaItalic`) and
/// via font symbolic traits (relative to `police` to avoid confusing a heading already bold by design).
public func attributedToSpans(_ attrStr: NSAttributedString, police: UIFont) -> [InlineTextFfi] {
    guard !attrStr.string.isEmpty else { return [] }
    var spans: [InlineTextFfi] = []
    let traitsBase = police.fontDescriptor.symbolicTraits
    let baseIsBold = traitsBase.contains(.traitBold)
    let baseIsItalic = traitsBase.contains(.traitItalic)
    attrStr.enumerateAttributes(in: NSRange(location: 0, length: attrStr.length)) { attrs, range, _ in
        let text = (attrStr.string as NSString).substring(with: range)
        guard !text.isEmpty else { return }
        var styles: [InlineStyleFfi] = []
        let fontTraits = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        let boldCustom = (attrs[.pinkhaBold] as? Bool) == true
        let italicCustom = (attrs[.pinkhaItalic] as? Bool) == true
        let boldFromFont = fontTraits.contains(.traitBold) && !baseIsBold
        let italicFromFont = fontTraits.contains(.traitItalic) && !baseIsItalic
        let italicFromObliqueness = attrs[.pinkhaObliqueness] != nil && !baseIsItalic

        if boldCustom || boldFromFont { styles.append(.bold) }
        if italicCustom || italicFromFont || italicFromObliqueness { styles.append(.italic) }
        if (attrs[.underlineStyle]     as? Int) != nil { styles.append(.underline) }
        if (attrs[.strikethroughStyle] as? Int) != nil { styles.append(.strikethrough) }
        if let nom = attrs[.pinkhaColor] as? String    { styles.append(.color(nom)) }
        if let url = attrs[.link]        as? URL       { styles.append(.link(url.absoluteString)) }
        if let level = attrs[.pinkhaParagraphIndentLevel] as? NSNumber {
            styles.append(.paragraphIndent(min(level.uint8Value, PinkhaParagraphIndent.maximumLevel)))
        }
        spans.append(InlineTextFfi(content: text, styles: styles))
    }
    return spans
}
