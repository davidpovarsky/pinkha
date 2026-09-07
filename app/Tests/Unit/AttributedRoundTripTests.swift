import Testing
import UIKit
import PinkhaFFI
import PinkhaRichText
@testable import Pinkha

// The spans ↔ NSAttributedString round-trip is the heart of rich text:
// if even one style is lost, the user loses their formatting.

@Suite("Spans ↔ NSAttributedString — round-trip")
struct AttributedRoundTripTests {

    private let font = UIFont.systemFont(ofSize: 17)

    @Test func emptySpansProducesEmptyString() {
        let attr = spansToAttributed([], police: font)
        #expect(attr.length == 0)
    }

    @Test func plainTextRoundTrips() {
        let spans = [InlineTextFfi(content: "Bonjour", styles: [])]
        let attr = spansToAttributed(spans, police: font)
        let back = attributedToSpans(attr, police: font)
        #expect(back.count == 1)
        #expect(back[0].content == "Bonjour")
        #expect(back[0].styles.isEmpty)
    }

    @Test func boldSurvivesRoundTrip() {
        let spans = [InlineTextFfi(content: "x", styles: [.bold])]
        let back = attributedToSpans(spansToAttributed(spans, police: font), police: font)
        #expect(back.first?.styles.contains(where: { if case .bold = $0 { true } else { false } }) == true)
    }

    @Test func italicSurvivesRoundTrip() {
        let spans = [InlineTextFfi(content: "x", styles: [.italic])]
        let back = attributedToSpans(spansToAttributed(spans, police: font), police: font)
        #expect(back.first?.styles.contains(where: { if case .italic = $0 { true } else { false } }) == true)
    }

    @Test func underlineSurvivesRoundTrip() {
        let spans = [InlineTextFfi(content: "x", styles: [.underline])]
        let back = attributedToSpans(spansToAttributed(spans, police: font), police: font)
        #expect(back.first?.styles.contains(where: { if case .underline = $0 { true } else { false } }) == true)
    }

    @Test func strikethroughSurvivesRoundTrip() {
        let spans = [InlineTextFfi(content: "x", styles: [.strikethrough])]
        let back = attributedToSpans(spansToAttributed(spans, police: font), police: font)
        #expect(back.first?.styles.contains(where: { if case .strikethrough = $0 { true } else { false } }) == true)
    }

    @Test func colorSurvivesRoundTripWithName() {
        let spans = [InlineTextFfi(content: "x", styles: [.color("rouge")])]
        let back = attributedToSpans(spansToAttributed(spans, police: font), police: font)
        if case .color(let name) = back.first?.styles.first {
            #expect(name == "rouge")
        } else {
            Issue.record("color 'rouge' should have survived the round-trip")
        }
    }

    @Test func linkSurvivesRoundTrip() {
        let spans = [InlineTextFfi(content: "x", styles: [.link("https://pinkha.app")])]
        let back = attributedToSpans(spansToAttributed(spans, police: font), police: font)
        if case .link(let url) = back.first?.styles.first {
            #expect(url == "https://pinkha.app")
        } else {
            Issue.record("link should have survived the round-trip")
        }
    }

    @Test func combinedBoldItalicRoundTrips() {
        let spans = [InlineTextFfi(content: "x", styles: [.bold, .italic])]
        let back = attributedToSpans(spansToAttributed(spans, police: font), police: font)
        let styles = Set(back.flatMap(\.styles).map(StyleKey.from))
        #expect(styles.contains(.bold))
        #expect(styles.contains(.italic))
    }

    @Test func semanticParagraphAndLineSeparatorsRoundTrip() {
        let content = "פסקה א\u{2029}פסקה ב\u{2028}שורה"
        let spans = [InlineTextFfi(content: content, styles: [.bold])]
        let attributed = spansToAttributed(spans, police: font)
        #expect(attributed.string == content)
        #expect(attributedToSpans(attributed, police: font).map(\.content).joined() == content)
        let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(abs((style?.paragraphSpacing ?? 0) - font.lineHeight * 0.45) < 0.01)
    }

    @Test func legacyNewlineNormalizesToSoftLineSeparator() {
        let attributed = spansToAttributed(
            [InlineTextFfi(content: "ישן\nחדש", styles: [.italic])], police: font)
        #expect(attributed.string == "ישן\u{2028}חדש")
        let styles = attributedToSpans(attributed, police: font).flatMap(\.styles).map(StyleKey.from)
        #expect(styles.contains(.italic))
    }

    @Test func paragraphIndentRoundTripsWithEveryInlineCombination() {
        let combinations: [[InlineStyleFfi]] = [
            [.paragraphIndent(2)], [.paragraphIndent(2), .bold],
            [.paragraphIndent(2), .italic], [.paragraphIndent(2), .color("blue")],
            [.paragraphIndent(2), .link("https://pinkha.app")]
        ]
        for styles in combinations {
            let back = attributedToSpans(
                spansToAttributed([.init(content: "text", styles: styles)], police: font),
                police: font)
            let keys = Set(back.flatMap(\.styles).map(StyleKey.from))
            for style in styles { #expect(keys.contains(StyleKey.from(style))) }
        }
    }

    @Test func paragraphSpacingIndentAndRTLCoexist() {
        let attributed = spansToAttributed(
            [.init(content: "פסקה", styles: [.paragraphIndent(3)])],
            police: font, writingDirection: .rightToLeft)
        let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            as? NSParagraphStyle
        #expect(style?.baseWritingDirection == .rightToLeft)
        #expect(abs((style?.headIndent ?? 0) - font.lineHeight * 1.3 * 3) < 0.01)
        #expect(abs((style?.paragraphSpacing ?? 0) - font.lineHeight * 0.45) < 0.01)
    }

    @Test func paragraphRangesDistinguishSoftAndParagraphSeparators() {
        let text = "a\u{2028}b\u{2029}c"
        let softLineSelection = NSRange(location: 2, length: 1)
        #expect(PinkhaParagraphIndent.ranges(in: text, intersecting: softLineSelection)
            == [NSRange(location: 0, length: 4)])
        let acrossParagraphs = NSRange(location: 0, length: (text as NSString).length)
        #expect(PinkhaParagraphIndent.ranges(in: text, intersecting: acrossParagraphs)
            == [NSRange(location: 0, length: 4), NSRange(location: 4, length: 1)])
    }

    @Test func caretAndThreeParagraphSelectionChangeExpectedRangesAndClamp() {
        let text = "one\u{2029}two\u{2029}three"
        let attributed = NSMutableAttributedString(
            attributedString: spansToAttributed([.init(content: text, styles: [])], police: font))
        #expect(PinkhaParagraphIndent.apply(
            delta: 1, to: attributed, selection: NSRange(location: 5, length: 0), font: font))
        let ranges = PinkhaParagraphIndent.ranges(
            in: text, intersecting: NSRange(location: 0, length: attributed.length))
        #expect(ranges.map { PinkhaParagraphIndent.level(in: attributed, range: $0) } == [0, 1, 0])
        #expect(PinkhaParagraphIndent.apply(
            delta: 1, to: attributed, selection: NSRange(location: 0, length: attributed.length), font: font))
        #expect(ranges.map { PinkhaParagraphIndent.level(in: attributed, range: $0) } == [1, 2, 1])
        for _ in 0..<10 {
            _ = PinkhaParagraphIndent.apply(
                delta: -1, to: attributed,
                selection: NSRange(location: 0, length: attributed.length), font: font)
        }
        #expect(ranges.map { PinkhaParagraphIndent.level(in: attributed, range: $0) } == [0, 0, 0])
        #expect(!PinkhaParagraphIndent.canChange(
            by: -1, in: attributed, selection: NSRange(location: 0, length: attributed.length)))
    }
}

/// Reduces `InlineStyleFfi` to a simple Hashable identifier for tests
/// (the real type is not Hashable because of its associated-value cases).
private enum StyleKey: Hashable {
    case bold, italic, underline, strikethrough, color(String), link(String), paragraphIndent(UInt8)
    static func from(_ s: InlineStyleFfi) -> StyleKey {
        switch s {
        case .bold:           return .bold
        case .italic:         return .italic
        case .underline:      return .underline
        case .strikethrough:  return .strikethrough
        case .color(let n):   return .color(n)
        case .link(let u):    return .link(u)
        case .paragraphIndent(let level): return .paragraphIndent(level)
        }
    }
}
